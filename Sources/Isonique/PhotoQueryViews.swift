import SwiftUI
import IsoniqueCore

struct SmartAlbumView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rule = SmartAlbumRule()
    @State private var query = PhotoQuery()

    private var combinedRule: SmartAlbumRule {
        var result = rule
        result.query = query.criteria.isEmpty ? nil : query
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(model.editingSmartAlbum == nil ? "New Smart Album" : "Edit Smart Album").font(.title2.bold())
            TextField("Album name", text: $name)
            Picker("Search within", selection: $rule.projectID) {
                Text("Entire Library").tag(nil as UUID?)
                ForEach(model.library.projects) { project in Text(project.name).tag(Optional(project.id)) }
            }
            DisclosureGroup("Basic filters") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Rating", selection: Binding(get: { rule.selectedRatingFilter }, set: { rule.setRatingFilter($0) })) {
                        ForEach(RatingFilter.allCases) { filter in Text(filter.label).tag(filter) }
                    }
                    Toggle("Flagged photos only", isOn: $rule.flaggedOnly)
                    TextField("Name, caption, keyword or camera contains", text: $rule.text)
                }.padding(.vertical, 8)
            }
            Divider()
            PhotoQueryBuilder(query: $query)
            Text("The project scope and basic filters apply to every result. Album membership updates as photos change.")
                .font(.caption).foregroundStyle(.secondary)
            let current = combinedRule
            let count = model.library.activePhotos.filter { photo in
                current.includes(photo, originalAvailable: { model.isOriginalAvailable(photo) })
            }.count
            Text("\(count) matching photos")
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.editingSmartAlbum == nil ? "Create" : "Save") {
                    if model.saveSmartAlbum(name: name, rule: current, editingID: model.editingSmartAlbum) { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !query.criteria.allSatisfy(\.isValid))
            }
        }.padding(26).frame(width: 650).onAppear {
            if let album = model.library.albums.first(where: { $0.id == model.editingSmartAlbum }), let savedRule = album.rule {
                name = album.name
                rule = savedRule
                query = savedRule.query ?? PhotoQuery()
            } else {
                rule.setRatingFilter(.all)
                rule.projectID = model.library.projects.first { model.scope == "project:\($0.id)" }?.id
            }
        }
    }
}

struct AdvancedSearchView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = PhotoQuery()
    @State private var albumName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Advanced Search").font(.title2.bold())
            Text("Search within \(model.title). Quick search and browser filters also apply.").foregroundStyle(.secondary)
            PhotoQueryBuilder(query: $query)
            Text("\(model.filteredPhotos(advancedQuery: query).count) matching photos")
            Divider()
            TextField("Name for a saved Smart Album", text: $albumName)
            Text("A saved album uses these rules and the current project scope, if there is one. Quick filters stay in the Browser.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save as Smart Album") {
                    var rule = SmartAlbumRule()
                    rule.setRatingFilter(.all)
                    rule.query = query
                    rule.projectID = model.library.projects.first { model.scope == "project:\($0.id)" }?.id
                    if model.saveSmartAlbum(name: albumName, rule: rule) { dismiss() }
                }.disabled(model.isViewingTrash || query.criteria.isEmpty || !valid || albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Apply Search") {
                    model.advancedSearch = query.criteria.isEmpty ? nil : query
                    model.showBrowser()
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(26).frame(width: 650)
            .onAppear { query = model.advancedSearch ?? PhotoQuery() }
    }

    private var valid: Bool { query.criteria.allSatisfy(\.isValid) }
}

private struct PhotoQueryBuilder: View {
    @Binding var query: PhotoQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Match", selection: $query.match) {
                    ForEach(PhotoQueryMatch.allCases) { match in Text(match.rawValue).tag(match) }
                }.fixedSize()
                Spacer()
                Button("Add Rule", systemImage: "plus") { query.criteria.append(PhotoQueryCriterion()) }
            }
            if query.criteria.isEmpty {
                Text("Add a rule to filter by metadata, date, rating or original status.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($query.criteria) { $criterion in
                            HStack(spacing: 8) {
                                PhotoQueryRow(criterion: $criterion)
                                Button("Remove Rule", systemImage: "minus.circle") {
                                    let id = criterion.id
                                    query.criteria.removeAll { $0.id == id }
                                }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                        }
                    }.padding(2)
                }.frame(height: min(CGFloat(query.criteria.count * 34 + 4), 190))
                if !query.criteria.allSatisfy(\.isValid) {
                    Text("Complete every rule. Enter dates as YYYY-MM-DD.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PhotoQueryRow: View {
    @Binding var criterion: PhotoQueryCriterion
    @EnvironmentObject var model: Workspace

    var body: some View {
        Picker("Field", selection: $criterion.field) {
            ForEach(PhotoQueryField.allCases) { field in Text(LocalizedStringKey(field.rawValue)).tag(field) }
        }.labelsHidden().accessibilityLabel("Rule field").frame(width: 155)
        Picker("Comparison", selection: $criterion.comparison) {
            ForEach(criterion.field.operators) { comparison in Text(comparison.rawValue).tag(comparison) }
        }.labelsHidden().accessibilityLabel("Rule comparison").frame(width: 148)
        valueField
            .onChange(of: criterion.field) { _, field in
                if let operation = field.operators.first { criterion.comparison = operation }
                criterion.keywordPath = nil
                criterion.gpsRadius = nil
                switch field {
                case .rating: criterion.value = "3"
                case .colorLabel: criterion.value = "1"
                case .flag, .storage, .availability, .adjusted: criterion.value = "true"
                default: criterion.value = ""
                }
            }
    }

    @ViewBuilder private var valueField: some View {
        if !criterion.comparison.needsValue {
            Spacer(minLength: 0)
        } else {
            comparisonValueField
        }
    }

    @ViewBuilder private var comparisonValueField: some View {
        switch criterion.field {
        case .exifShutterSpeed: TextField("1/125 or 0.008 s", text: $criterion.value).accessibilityLabel("Rule shutter speed")
        case .exifAperture: TextField("e.g. f/2.8", text: $criterion.value).accessibilityLabel("Rule aperture")
        case .exifISO: TextField("e.g. 400", text: $criterion.value).accessibilityLabel("Rule ISO")
        case .exifFocalLength: TextField("e.g. 35 mm", text: $criterion.value).accessibilityLabel("Rule focal length")
        case .exifLens: TextField("Lens name", text: $criterion.value).accessibilityLabel("Rule lens name")
        case .person: TextField("Person’s name", text: $criterion.value).accessibilityLabel("Rule person name")
        case .gpsLatitude: TextField("e.g. 51.5", text: $criterion.value).accessibilityLabel("Rule latitude")
        case .gpsLongitude: TextField("e.g. -0.125", text: $criterion.value).accessibilityLabel("Rule longitude")
        case .gpsLocation:
            HStack(spacing: 6) {
                TextField("Latitude", text: radiusInput(\.latitude)).accessibilityLabel("Radius centre latitude")
                TextField("Longitude", text: radiusInput(\.longitude)).accessibilityLabel("Radius centre longitude")
                TextField("km", text: radiusInput(\.kilometres)).accessibilityLabel("Radius in kilometres")
            }
        case .flag: booleanPicker("Flagged", "Unflagged")
        case .storage: booleanPicker("Referenced", "Managed")
        case .availability: booleanPicker("Available", "Unavailable")
        case .adjusted: booleanPicker("Adjusted", "Unadjusted")
        case .rating:
            Picker("Rating", selection: $criterion.value) {
                Text("Rejected").tag("-1")
                Text("Unrated").tag("0")
                ForEach(1...5, id: \.self) { Text("\($0) stars").tag(String($0)) }
            }.labelsHidden().accessibilityLabel("Rule rating")
        case .keywordPath:
            let choices = model.keywordPathChoices
            Picker("Keyword path", selection: $criterion.keywordPath) {
                Text("Choose a keyword path").tag(nil as KeywordPath?)
                if let saved = criterion.keywordPath, !choices.contains(saved) {
                    Text(saved.title).tag(Optional(saved))
                }
                ForEach(choices, id: \.self) { path in
                    Text(path.title).tag(Optional(path))
                }
            }.labelsHidden().accessibilityLabel("Rule keyword path")
        case .colorLabel:
            Picker("Color label", selection: $criterion.value) {
                Text("No label").tag("0")
                ForEach(PhotoColorLabel.allCases) { label in Text(model.name(for: label)).tag(String(label.rawValue)) }
            }.labelsHidden().accessibilityLabel("Rule color label")
        case .captured, .imported: TextField("YYYY-MM-DD", text: $criterion.value).accessibilityLabel("Rule date")
        case .format: TextField("Extension, e.g. jpg", text: $criterion.value).accessibilityLabel("Rule file extension")
        default: TextField("Value", text: $criterion.value).accessibilityLabel("Rule value")
        }
    }

    private func radiusInput(_ field: WritableKeyPath<GPSRadiusRule, String>) -> Binding<String> {
        Binding(get: { criterion.gpsRadius?[keyPath: field] ?? "" }, set: { value in
            var radius = criterion.gpsRadius ?? GPSRadiusRule()
            radius[keyPath: field] = value
            criterion.gpsRadius = radius
        })
    }

    private func booleanPicker(_ affirmative: String, _ negative: String) -> some View {
        Picker("Value", selection: $criterion.value) {
            Text(affirmative).tag("true")
            Text(negative).tag("false")
        }.labelsHidden().accessibilityLabel("Rule value")
    }
}
