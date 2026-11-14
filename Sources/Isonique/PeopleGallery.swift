import IsoniqueCore
import SwiftUI

struct PeopleGallery {
    struct Person: Identifiable {
        let id: String
        let name: String
        var total = 0
        var projectCounts: [UUID: Int] = [:]
        var portrait: PersonOverview.Face

        func count(in project: UUID?) -> Int {
            guard let project else { return total }
            return projectCounts[project, default: 0]
        }

        mutating func considerPortrait(_ candidate: PersonOverview.Face) {
            let chosen = portrait.face.representativeChosenAt
            let proposed = candidate.face.representativeChosenAt
            if chosen != proposed {
                guard let proposed, chosen.map({ proposed > $0 }) ?? true else { return }
            } else if candidate.photo.importedAt != portrait.photo.importedAt {
                guard candidate.photo.importedAt < portrait.photo.importedAt else { return }
            } else if candidate.photo.id != portrait.photo.id {
                guard candidate.photo.id.uuidString < portrait.photo.id.uuidString else { return }
            } else {
                guard candidate.number < portrait.number else { return }
            }
            portrait = candidate
        }

        mutating func add(_ candidate: PersonOverview.Face, countVersion: Bool) {
            considerPortrait(candidate)
            if countVersion {
                total += 1
                if let project = candidate.photo.projectID { projectCounts[project, default: 0] += 1 }
            }
        }
    }

    let people: [Person]

    init(library: Library) {
        var groups: [String: Person] = [:]
        for photo in library.photos where photo.trashedAt == nil {
            var counted: Set<String> = []
            for (index, face) in (photo.people?.faces ?? []).enumerated() {
                guard let name = face.name else { continue }
                let key = PhotoFace.personKey(name)
                let candidate = PersonOverview.Face(photo: photo, face: face, number: index + 1)
                groups[key, default: Person(id: key, name: name, portrait: candidate)]
                    .add(candidate, countVersion: counted.insert(key).inserted)
            }
        }
        people = groups.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func matching(name search: String, project: UUID?) -> [Person] {
        let term = PhotoFace.personKey(search.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        return people.filter { $0.count(in: project) > 0 && (term.isEmpty || $0.id.contains(term)) }
    }
}

extension Workspace {
    var isPeopleGallery: Bool { scope == "people-gallery" }

    var peopleGallery: PeopleGallery {
        if let peopleGallerySnapshot { return peopleGallerySnapshot }
        let gallery = PeopleGallery(library: library)
        peopleGallerySnapshot = gallery
        return gallery
    }

    func browseGalleryPerson(_ person: PeopleGallery.Person, project: UUID?) {
        guard !busy, repository != nil,
              project.map({ id in library.projects.contains { $0.id == id } }) ?? true,
              let current = peopleGallery.people.first(where: { $0.id == person.id && $0.count(in: project) > 0 }) else { return }
        showBrowser(allPhotos: true)
        places = false
        if let project {
            scope = "project:\(project)"
            var query = PhotoQuery()
            query.criteria = [PhotoQueryCriterion(field: .person, comparison: .equals, value: current.name)]
            advancedSearch = query
        } else {
            scope = "person:\(person.id)"
        }
        selectAfterChange(preferred: selection)
    }
}

struct PeopleGalleryView: View {
    @EnvironmentObject private var model: Workspace
    @State private var project: UUID?

    var body: some View {
        let people = model.peopleGallery.matching(name: model.peopleGallerySearch, project: project)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(people.count == 1 ? "1 person" : "\(people.count) people")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Project", selection: $project) {
                    Text("Entire Library").tag(nil as UUID?)
                    ForEach(model.library.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .frame(maxWidth: 295)
                Button("Review Summary…") {
                    model.openPeopleSummary(project.map { .project($0) } ?? .library)
                }
                .disabled(!model.canOpenUnnamedFaces)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            if people.isEmpty {
                if model.peopleGallery.people.isEmpty {
                    ContentUnavailableView("No Named People", systemImage: "person.crop.rectangle",
                        description: Text("Use Review Unnamed Faces to assign names to saved faces."))
                } else {
                    ContentUnavailableView("No Matching People", systemImage: "magnifyingglass",
                        description: Text("Try a different name or project."))
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 152), spacing: 16)], spacing: 16) {
                        ForEach(people) { person in
                            PeopleGalleryTile(person: person, count: person.count(in: project)) {
                                model.browseGalleryPerson(person, project: project)
                            }
                            .contextMenu {
                                Button("Person Overview…") {
                                    if let group = model.peopleGroups.first(where: { $0.id == person.id }) {
                                        model.openPersonOverview(group)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .accessibilityLabel("People Gallery")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.library.projects.map(\.id)) { _, available in
            if let project, !available.contains(project) { self.project = nil }
        }
    }
}

private struct PeopleGalleryTile: View {
    let person: PeopleGallery.Person
    let count: Int
    let browse: () -> Void
    @State private var portraitVisible = false

    var body: some View {
        Button(action: browse) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if portraitVisible {
                        PersonPortraitPreview(face: person.portrait, compact: true)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 138)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .onScrollVisibilityChange(threshold: 0.01) { portraitVisible = $0 }
                Text(person.name).font(.headline).lineLimit(1)
                Text(count == 1 ? "1 photo version" : "\(count) photo versions")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Browse photos of this person")
    }
}
