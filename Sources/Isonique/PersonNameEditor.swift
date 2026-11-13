import IsoniqueCore
import SwiftUI

struct PersonNameEditorRequest: Identifiable {
    let id = UUID()
    let person: PeopleGroup
    let root: URL
}

extension Workspace {
    var selectedPersonGroup: PeopleGroup? { peopleGroups.first { $0.scope == scope } }

    func openPersonNameEditor(_ group: PeopleGroup) {
        guard !busy, let repository, peopleGroups.contains(where: { $0.id == group.id }) else { return }
        personNameEditor = PersonNameEditorRequest(person: group, root: repository.root)
    }

    func cancelPersonNameEditor() { personNameEditor = nil }

    @discardableResult
    func applyPersonNameReview(_ review: PersonNameReview, request: PersonNameEditorRequest) -> Bool {
        guard !busy, personNameEditor?.id == request.id, repository?.root == request.root,
              PhotoFace.personKey(review.sourceName) == request.person.id else { return false }
        var draft = library
        guard let inverse = draft.applyPersonNameReview(review) else {
            error = "The library changed. Review the name change again."
            return false
        }
        var nextHistory = history
        nextHistory.record(.personName(inverse))
        guard commit(draft, history: nextHistory) else { return false }
        refreshPersonNameScopes(from: inverse.destinationKey, to: inverse.sourceKey)
        status = "Updated People assignments and exact-name rules"
        personNameEditor = nil
        return true
    }

    func refreshPersonNameScopes(from sourceKey: String, to destinationKey: String, onlyIfSourceVanished: Bool = false) {
        let source = "person:\(sourceKey)"
        let destination = "person:\(destinationKey)"
        let groups = peopleGroups
        if !onlyIfSourceVanished || !groups.contains(where: { $0.id == sourceKey }) {
            let nextScope = groups.contains(where: { $0.id == destinationKey }) ? destination : "people"
            if scope == source { scope = nextScope }
            if secondaryBrowser.scope == source { secondaryBrowser.scope = nextScope }
        }
        if selected == nil { selectAfterChange(preferred: selection) }
        if batchMode { batchSelection.formIntersection(photos.map(\.id)) }
        if secondaryBrowser.visible, secondarySelected == nil {
            secondaryBrowserSelection = secondaryPhotos.first?.id
        }
    }
}

struct PersonNameEditor: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case rename = "Rename"
        case merge = "Merge"
        var id: Self { self }
    }

    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    let request: PersonNameEditorRequest
    @State private var mode = Mode.rename
    @State private var name: String
    @State private var destination = ""
    @State private var review: PersonNameReview?
    @State private var failure: String?

    init(request: PersonNameEditorRequest) {
        self.request = request
        _name = State(initialValue: request.person.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename or Merge Person").font(.title2.bold())
            if let review {
                Text("From \(review.sourceName) to \(review.destinationName)").font(.headline)
                changes(review)
            } else {
                Text(request.person.name).foregroundStyle(.secondary)
                Picker("Action", selection: $mode) {
                    ForEach(Mode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented)
                if mode == .rename {
                    TextField("New name", text: $name)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Merge into", selection: $destination) {
                        Text("Choose a person").tag("")
                        ForEach(mergeChoices, id: \.key) { person in
                            Text(person.value).tag(person.key)
                        }
                    }
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                if review != nil {
                    Button("Back") { review = nil; failure = nil }
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.cancelPersonNameEditor()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                if let review {
                    Button(mode == .rename ? "Apply Rename" : "Merge People") {
                        if model.applyPersonNameReview(review, request: request) { dismiss() }
                        else {
                            failure = model.error ?? String(localized: "The name change could not be saved.")
                            model.error = nil
                        }
                    }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Preview Changes", action: makeReview)
                        .keyboardShortcut(.defaultAction)
                        .disabled(mode == .merge && destination.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .onChange(of: mode) { _, _ in failure = nil }
        .onChange(of: name) { _, _ in failure = nil }
        .onChange(of: destination) { _, _ in failure = nil }
    }

    private var mergeChoices: [(key: String, value: String)] {
        model.library.personNamesByKey.filter { $0.key != request.person.id }
            .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }

    private func changes(_ review: PersonNameReview) -> some View {
        List {
            Section("Photo Versions (\(review.photos.count))") {
                if review.photos.isEmpty { Text("No photo assignments will change.").foregroundStyle(.secondary) }
                ForEach(review.photos) { photo in
                    HStack {
                        Text(photo.name)
                        if photo.inTrash { Label("In Trash", systemImage: "trash").font(.caption) }
                        Spacer()
                        Text(photo.faceCount == 1 ? "1 face" : "\(photo.faceCount) faces").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Smart Album Rules (\(review.rules.count))") {
                if review.rules.isEmpty { Text("No exact-name rules will change.").foregroundStyle(.secondary) }
                ForEach(review.rules) { rule in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.album)
                        let comparison = String(localized: String.LocalizationValue(rule.comparison.rawValue))
                        Text("Person \(comparison): \(rule.before) → \(rule.after)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 260)
    }

    private func makeReview() {
        do {
            let action: PersonNameAction = mode == .rename ? .rename(name) : .merge(intoKey: destination)
            review = try model.library.reviewPersonName(request.person.id, action: action)
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}
