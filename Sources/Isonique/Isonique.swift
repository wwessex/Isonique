import SwiftUI
import AppKit
import ImageIO
import IsoniqueCore
import UniformTypeIdentifiers

enum PhotoSort: String, CaseIterable, Identifiable, Codable {
    case manual = "Manual order", imported = "Import date", name = "Filename", rating = "Rating", captured = "Capture date"
    var id: String { rawValue }
}
enum EditTool: String { case select, crop, straighten, brush, spot, redEye }
@MainActor final class Workspace: ObservableObject {
    @Published var library = Library() {
        didSet {
            browserSnapshot = nil
            peopleGroupsSnapshot = nil
            peopleGallerySnapshot = nil
            unnamedFaceQueueSnapshot = nil
        }
    }
    @Published var scope = "all"
    @Published var selection: UUID?
    @Published var batchMode = false
    @Published var batchSelection: Set<UUID> = []
    @Published var showAutoStack = false
    @Published var showSlideshow = false
    @Published var slideshowPhotos: [Photo] = []
    @Published var showSmartAlbum = false
    @Published var showAdvancedSearch = false
    @Published var peopleReview: PeopleReview?
    @Published var unnamedFaceReview: UnnamedFaceReview?
    @Published var peopleSummary: PeopleSummaryRequest?
    var pendingPeopleSummaryAction: (root: URL, action: PeopleSummaryAction)?
    @Published var personNameEditor: PersonNameEditorRequest?
    @Published var personOverview: PersonOverviewRequest?
    @Published var peopleScan: PeopleScanJob?
    var peopleGroupsSnapshot: [PeopleGroup]?
    var peopleGallerySnapshot: PeopleGallery?
    @Published var peopleGallerySearch = ""
    var unnamedFaceQueueSnapshot: (scope: UnnamedFaceScope, items: [UnnamedFaceItem])?
    @Published var advancedSearch: PhotoQuery?
    @Published var editingSmartAlbum: UUID?
    @Published var search = ""
    @Published var sort = PhotoSort.imported {
        didSet {
            guard let browserPreferencePrefix else { return }
            preferences.set(sort.rawValue, forKey: "\(browserPreferencePrefix).sort")
        }
    }
    @Published var sortDescending = false {
        didSet {
            guard let browserPreferencePrefix else { return }
            preferences.set(sortDescending, forKey: "\(browserPreferencePrefix).sortDescending")
        }
    }
    @Published var stampGroups = Set(AdjustmentGroup.allCases.filter { $0 != .localBrush && $0 != .retouch && $0 != .redEye })
    @Published var ratingFilter = RatingFilter.all
    @Published var originalFilter = OriginalFilter.all
    @Published var colorFilter = ColorLabelFilter.all
    @Published var labelNames: [String: String]
    @Published var originalStatusRevision = 0
    @Published var originalJobResult: OriginalJobResult?
    @Published var projectMergeTask: Task<ProjectLibraryMergeResult, Error>?
    @Published var libraryMergeTask: Task<LibraryMergeResult, Error>?
    @Published var projectImportTask: Task<ProjectLibraryImportResult, Error>?
    @Published var projectExportTask: Task<Int, Error>?
    @Published var originalJobTask: Task<(Library?, OriginalJobResult), Error>?
    @Published var busy = false
    @Published private(set) var importInProgress = false
    @Published private(set) var importProgress: ImportProgress?
    @Published private(set) var cancellingImport = false
    private var importTask: Task<(Library, ImportReport), Never>?
    @Published var status = "Ready · originals are preserved"
    @Published var error: String?
    @Published var viewer = false
    @Published var places = false
    @Published var showLoupe = false
    @Published var curveSampling: CurveSamplingRequest?
    @Published var whiteBalanceSampling: WhiteBalanceSamplingRequest?
    @Published var targetedColorSampling: TargetedColorSamplingRequest?
    @Published var targetedColorSelection: UUID?
    @Published var curvePointSelection: CurvePointSelection?
    @Published var browserLayout: BrowserPresentation
    @Published var quickPreview = false {
        didSet { preferences.set(quickPreview, forKey: "browser.quickPreview") }
    }
    @Published var secondaryBrowser = SecondaryBrowserConfiguration() {
        didSet { SecondaryBrowserPreferences.save(secondaryBrowser, to: preferences) }
    }
    @Published var activeBrowserPane = BrowserPaneFocus.primary
    @Published var secondaryBrowserSelection: UUID?
    @Published var listColumnCustomization = TableColumnCustomization<Photo>() {
        didSet { ListColumnPreferences.save(listColumnCustomization, to: preferences) }
    }
    @Published var gridThumbnailSize: GridThumbnailSize {
        didSet { preferences.set(gridThumbnailSize.rawValue, forKey: GridThumbnailSize.preferenceKey) }
    }
    @Published var showInspector = true
    @Published var photographyMode = PhotographyWorkspaceMode.editing
    @Published var photographyLayout = PhotographyWorkspaceLayout.defaultValue(for: .editing)
    @Published var photographyFocus = PhotographyWorkspaceFocus.viewer
    @Published var isPhotographyFullScreen = false
    @Published var secondaryViewerVisible = false
    @Published var toolbarConfiguration = IsoniqueToolbarConfiguration()
    @Published var commandPreferences = KeyboardCommandPreferences()
    @Published var showToolbarEditor = false
    @Published var showCommandEditor = false
    @Published var showListColumnEditor = false
    @Published var compareOriginal = false
    @Published var comparisonID: UUID?
    @Published var comparisonIDs: [UUID] = []
    @Published var tool = EditTool.select
    @Published var brushAdjustment = LocalBrushAdjustment.dodge
    @Published var brushInstanceID: UUID?
    @Published var spotMode = SpotRemovalMode.repair
    @Published var selectedSpotID: UUID?
    @Published var spotDraftSource: BrushPoint?
    @Published var spotPlacement = SpotPointKind.source
    @Published var selectedRedEyeID: UUID?
    @Published var liftedAdjustments: LiftedSettings?
    @Published var liftLookupID: UUID?
    @Published var stampMetadata = Set<StampMetadata>()
    @Published var showRelocationOptions = false
    var pendingRelocationOptions: OriginalRelocationOptions?
    @Published var showExportOptions = false
    @Published var showPrintOptions = false
    @Published var externalEditHandoff: ExternalEditHandoff?
    @Published var keywordVocabulary: KeywordVocabulary
    @Published var showKeywordVocabulary = false
    @Published var keywordGroups: KeywordGroupPreferences
    @Published var metadataPresets: [MetadataPreset]
    @Published var adjustmentPresets: [CustomAdjustmentPreset]
    @Published var showAdjustmentPresetManager = false
    @Published var adjustmentPresetReview: AdjustmentPresetApplicationReview? = nil
    @Published var metadataViews: MetadataViewPreferences
    @Published var showKeywordControls: Bool {
        didSet { preferences.set(showKeywordControls, forKey: KeywordGroupPreferences.controlsKey) }
    }
    @Published var showKeywordGroupEditor = false
    @Published var batchMetadataReview: BatchMetadataReview?
    @Published var inheritedIPTCReview: InheritedIPTCReview?
    @Published var inheritedIPTCScan: Task<InheritedIPTCReview, Error>?
    @Published var originalMetadataCatalogueTask: Task<(Library, MetadataCatalogueResult), Error>?
    @Published var locationEditor: PhotoLocationEdit?
    @Published var gpxLocationEditor: GPXLocationEdit?
    @Published var gpxWaypointAssignment: GPXWaypointAssignment?
    @Published var captureDateCorrection: CaptureDateCorrection?
    @Published var showImportOptions = false
    @Published var pendingImport: [URL] = []
    @Published var pendingDeviceImport: DeviceImportSelection?
    @Published var showDeviceImport = false
    @Published var tetherCaptureSource: TetherCaptureSource?
    let cameraDiscovery = CameraDiscovery()
    var hasPendingImport: Bool { !pendingImport.isEmpty || pendingDeviceImport != nil }
    @Published var proofProfile: Data?
    @Published var proofName = ""
    @Published var proofEnabled = false
    @Published var clipping: ClippingSettings {
        didSet { clipping.save(to: preferences) }
    }
    @Published var history = EditHistory()
    let viewerRenderCache = ViewerRenderCache()
    let thumbnailCache = ThumbnailCache()
    static let recentLibraryLimit = 10
    static let recentLibraryKey = "library.recentRoots"
    @Published var recentLibraryPaths: [String] {
        didSet { preferences.set(recentLibraryPaths, forKey: Self.recentLibraryKey) }
    }
    let preferences: UserDefaults
    private var browserPreferencePrefix: String?
    var photographyWorkspacePreferences = PhotographyWorkspacePreferences()
    weak var photographyWindow: NSWindow?
    var photographyWindowObservers: [NSObjectProtocol] = []
    var keyboardCommandMonitor: Any?
    lazy var secondaryDisplayController = SecondaryDisplayViewerController(workspace: self)
    private var browserSnapshot: BrowserSnapshot?
    private struct BrowserSnapshot {
        struct Key: Equatable {
            let scope: String
            let places: Bool
            let search: String
            let query: PhotoQuery?
            let rating: RatingFilter
            let color: ColorLabelFilter
            let originals: OriginalFilter
            let sort: PhotoSort
            let descending: Bool
            let locale: String
            let timeZone: String
        }
        let key: Key
        let photos: [Photo]
        let indices: [UUID: Int]
    }
    var keepHistory: Bool { preferences.bool(forKey: "history.persist") }
    var canUndo: Bool { !history.undo.isEmpty }
    var canRedo: Bool { !history.redo.isEmpty }
    var repository: LibraryRepository?
    init(libraryRoot: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let storedRecents = preferences.stringArray(forKey: Self.recentLibraryKey) ?? []
        var seenPaths: Set<String> = []
        recentLibraryPaths = Array(storedRecents.filter { $0.hasPrefix("/") && seenPaths.insert($0).inserted }
            .prefix(Self.recentLibraryLimit))
        clipping = ClippingSettings(preferences: preferences)
        keywordVocabulary = KeywordVocabularyPreferences.load(from: preferences)
        keywordGroups = KeywordGroupPreferences.load(from: preferences)
        metadataPresets = MetadataPresetPreferences.load(from: preferences)
        adjustmentPresets = AdjustmentPresetPreferences.load(from: preferences)
        metadataViews = MetadataViewPreferences.load(from: preferences)
        showKeywordControls = preferences.bool(forKey: KeywordGroupPreferences.controlsKey)
        let layout = preferences.string(forKey: "browser.layout").flatMap(BrowserPresentation.init(rawValue:))
        browserLayout = layout == .list ? .list : .grid
        quickPreview = preferences.bool(forKey: "browser.quickPreview")
        secondaryBrowser = SecondaryBrowserPreferences.load(from: preferences)
        listColumnCustomization = ListColumnPreferences.load(from: preferences)
        gridThumbnailSize = preferences.string(forKey: GridThumbnailSize.preferenceKey)
            .flatMap(GridThumbnailSize.init(rawValue:)) ?? .standard
        labelNames = preferences.dictionary(forKey: "photo.labelNames") as? [String: String] ?? [:]
        toolbarConfiguration = IsoniqueToolbarConfiguration.load(from: preferences)
        commandPreferences = KeyboardCommandPreferences.load(from: preferences)
        restorePhotographyWorkspacePreferences()
        do {
            let args = ProcessInfo.processInfo.arguments
            let root: URL
            if let libraryRoot {
                root = libraryRoot
            } else if let index = args.firstIndex(of: "--library"), args.indices.contains(index + 1) {
                root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            } else if let saved = preferences.string(forKey: "library.selectedRoot") {
                root = URL(fileURLWithPath: saved, isDirectory: true)
                guard FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.json").path) else {
                    throw LibraryError.integrity("saved library is unavailable; use File → Open Isonique Library or Restore Library Backup")
                }
            } else {
                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                root = Self.defaultLibraryRoot(in: support)
            }
            let primaryPreferencePrefix = "browser.primary.\(root.standardizedFileURL.path)"
            browserPreferencePrefix = primaryPreferencePrefix
            sort = preferences.string(forKey: "\(primaryPreferencePrefix).sort")
                .flatMap(PhotoSort.init(rawValue:)) ?? .imported
            sortDescending = preferences.object(forKey: "\(primaryPreferencePrefix).sortDescending") as? Bool ?? false
            let repo = try LibraryRepository(root: root)
            library = try repo.openOrCreateCatalogue()
            repository = repo
            history = keepHistory ? (library.history ?? EditHistory()) : EditHistory()
            selection = photos.first?.id
        } catch { self.error = error.localizedDescription; status = "Library unavailable" }
    }
    static func defaultLibraryRoot(in support: URL) -> URL {
        let branded = support.appendingPathComponent("Isonique/Library", isDirectory: true)
        // Earlier Isonique builds stored their own catalogues here. Open them in place.
        let legacy = support.appendingPathComponent(
            "ApertureNative/Library", isDirectory: true
        )
        let files = FileManager.default
        if files.fileExists(atPath: branded.appendingPathComponent("catalog.json").path) {
            return branded
        }
        return files.fileExists(atPath: legacy.path) ? legacy : branded
    }
    var isViewingTrash: Bool { scope == "trash" }
    var photos: [Photo] {
        if isPeopleGallery {
            browserSnapshot = nil
            return []
        }
        let key = BrowserSnapshot.Key(scope: scope, places: usesPlacesPhotos, search: search, query: advancedSearch, rating: ratingFilter,
                                      color: colorFilter, originals: originalFilter, sort: sort,
                                      descending: sortDescending, locale: Locale.current.identifier,
                                      timeZone: TimeZone.current.identifier)
        if let snapshot = browserSnapshot, snapshot.key == key { return snapshot.photos }
        let visible = filteredPhotos(advancedQuery: advancedSearch)
        let albumQuery = currentAlbumID.flatMap { id in library.albums.first { $0.id == id }?.rule?.query }
        let readsAvailability = originalFilter == .unavailable ||
            advancedSearch?.criteria.contains { $0.field == .availability } == true ||
            albumQuery?.criteria.contains { $0.field == .availability } == true
        if readsAvailability {
            browserSnapshot = nil
        } else {
            let indices = Dictionary(visible.enumerated().map { ($0.element.id, $0.offset) },
                                     uniquingKeysWith: { first, _ in first })
            browserSnapshot = BrowserSnapshot(key: key, photos: visible, indices: indices)
        }
        return visible
    }

    func filteredPhotos(advancedQuery: PhotoQuery?, includingCollapsed: Bool = false, includingUnlocated: Bool = false) -> [Photo] {
        filteredPhotos(scope: scope, search: search, sort: sort, descending: sortDescending,
                       rating: ratingFilter, originals: originalFilter, color: colorFilter,
                       advancedQuery: advancedQuery, includingCollapsed: includingCollapsed,
                       placesOnly: usesPlacesPhotos, includingUnlocated: includingUnlocated)
    }

    func filteredPhotos(scope targetScope: String, search targetSearch: String, sort targetSort: PhotoSort,
                        descending: Bool, rating: RatingFilter, originals: OriginalFilter,
                        color: ColorLabelFilter, advancedQuery: PhotoQuery? = nil,
                        includingCollapsed: Bool = false, placesOnly: Bool = false,
                        includingUnlocated: Bool = false) -> [Photo] {
        let identifier = targetScope.split(separator: ":").last.flatMap { UUID(uuidString: String($0)) }
        let smartRule = targetScope.hasPrefix("album:") ? library.albums.first { $0.id == identifier }?.rule : nil
        let trash = targetScope == "trash"
        let candidates = library.photos.filter { photo in
            guard (photo.trashedAt != nil) == trash,
                  includingUnlocated || !placesOnly || photo.cataloguedLocation != nil else { return false }
            let inScope: Bool
            if targetScope.hasPrefix("project:"), let identifier { inScope = photo.projectID == identifier }
            else if targetScope.hasPrefix("album:"), let identifier {
                inScope = smartRule?.includes(photo, originalAvailable: { self.isOriginalAvailable(photo) }) ?? photo.albumIDs.contains(identifier)
            }
            else if targetScope.hasPrefix("stack:"), let identifier { inScope = photo.stackID == identifier }
            else if targetScope == "people" { inScope = photo.people?.faces.isEmpty == false }
            else if targetScope.hasPrefix("person:") {
                let person = String(targetScope.dropFirst("person:".count))
                inScope = photo.personNames.contains { PhotoFace.personKey($0) == person }
            }
            else { inScope = true }
            return inScope &&
                originals.includes(photo, repository: repository) &&
                color.includes(photo) &&
                BrowserFilterRules.includes(rating: photo.rating, flagged: photo.flagged, ratingFilter: rating, flaggedOnly: targetScope == "flagged") &&
                photo.matchesSearchText(targetSearch) &&
                (advancedQuery?.includes(photo, originalAvailable: { self.isOriginalAvailable(photo) }) ?? true)
        }
        let sorted: [Photo]
        if targetSort == .manual, let orderScope = manualOrderScope(for: targetScope) {
            let ordered = (library.browserOrders ?? BrowserOrderState()).ordered(candidates, in: orderScope)
            sorted = descending ? Array(ordered.reversed()) : ordered
        } else {
            let effectiveSort = targetSort == .manual ? PhotoSort.imported : targetSort
            sorted = candidates.sorted { lhs, rhs in
                descending ? orderedBefore(rhs, lhs, sort: effectiveSort) : orderedBefore(lhs, rhs, sort: effectiveSort)
            }
        }
        let albumID = targetScope.hasPrefix("album:") ? identifier : nil
        guard !includingCollapsed, !placesOnly, !trash, !targetScope.hasPrefix("stack:"),
              targetScope != "people", !targetScope.hasPrefix("person:"),
              let state = library.stackBrowser else { return sorted }
        return state.presenting(sorted, albumID: albumID)
    }

    func isOriginalAvailable(_ photo: Photo) -> Bool? {
        guard let repository else { return nil }
        return (try? repository.availableOriginalURL(photo)) != nil
    }

    @discardableResult
    func saveSmartAlbum(name: String, rule: SmartAlbumRule, editingID: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, rule.query?.criteria.allSatisfy(\.isValid) != false else { return false }
        var draft = library
        var album = Collection(name: trimmed)
        album.rule = rule
        if let editingID, let index = draft.albums.firstIndex(where: { $0.id == editingID }) {
            album.id = editingID
            draft.albums[index] = album
        } else {
            draft.albums.append(album)
        }
        if rule.query != nil || rule.projectID != nil { draft.version = max(draft.version, 2) }
        guard commit(draft) else { return false }
        showBrowser(allPhotos: true)
        scope = "album:\(album.id)"
        return true
    }
    private func orderedBefore(_ lhs: Photo, _ rhs: Photo, sort: PhotoSort) -> Bool {
        switch sort {
        case .manual: return lhs.importedAt == rhs.importedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.importedAt < rhs.importedAt
        case .imported: return lhs.importedAt == rhs.importedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.importedAt < rhs.importedAt
        case .name: return lhs.displayName == rhs.displayName ? lhs.id.uuidString < rhs.id.uuidString : lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        case .rating: return lhs.rating == rhs.rating ? lhs.importedAt < rhs.importedAt : lhs.rating < rhs.rating
        case .captured: return lhs.captureDate == rhs.captureDate ? lhs.importedAt < rhs.importedAt : lhs.captureDate < rhs.captureDate
        }
    }
    var selected: Photo? {
        guard let selection else { return nil }
        let visible = photos
        if let snapshot = browserSnapshot { return snapshot.indices[selection].map { visible[$0] } }
        return visible.first { $0.id == selection }
    }
    var title: String {
        if let lightTable = activeLightTable { return lightTable.name }
        if scope == "people" || isPeopleGallery { return "People" }
        if scope.hasPrefix("person:") { return peopleGroups.first { $0.scope == scope }?.name ?? "People" }
        if isViewingTrash { return "Trash" }
        if scope == "flagged" { return "Flagged" }
        if let project = library.projects.first(where: { scope == "project:\($0.id)" }) { return project.name }
        if let album = library.albums.first(where: { scope == "album:\($0.id)" }) { return album.name }
        if scope.hasPrefix("stack:") { return "Photo Stack" }
        return "All Photos"
    }
    @discardableResult
    func commit(_ draft: Library, history newHistory: EditHistory? = nil) -> Bool {
        guard !busy, let repository else { return false }
        let nextHistory = newHistory ?? history
        var saved = draft
        saved.history = keepHistory ? nextHistory : nil
        saved.upgradeForQuarterTones()
        saved.upgradeForChannelLevels()
        saved.upgradeForChannelCurves()
        saved.upgradeForBrushRecipes()
        saved.upgradeForSpotRemoval()
        saved.upgradeForDetailAdjustments()
        saved.upgradeForLensEffects()
        saved.upgradeForKelvinWhiteBalance()
        saved.upgradeForTargetedColors()
        saved.upgradeForBlackAndWhite()
        saved.upgradeForRedEye()
        saved.upgradeForDefinition()
        saved.upgradeForAdvancedLocalBrushes()
        saved.upgradeForExtendedLocalBrushes()
        saved.upgradeForLocalDetailBrushes()
        saved.upgradeForLocalContrastBlur()
        saved.upgradeForLocalTintSkin()
        saved.upgradeForLocalBrushInstances()
        saved.upgradeForLocalPolarizeHalo()
        saved.upgradeForPressureBrushes()
        saved.upgradeForLightTables()
        saved.upgradeForBrowserOrders()
        do {
            library = try repository.save(saved)
            if newHistory != nil { history = nextHistory }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func save() { commit(library) }
    func undoEdit() { stepHistory(redo: false) }
    func redoEdit() { stepHistory(redo: true) }
    private func stepHistory(redo: Bool) {
        var nextHistory = history
        var draft = library
        guard let entry = nextHistory.step(in: &draft, redoing: redo),
              commit(draft, history: nextHistory) else { return }
        if case .lightTables = entry {
            if activeLightTableID != nil, activeLightTable == nil { scope = "all" }
        } else if case .browserOrders = entry {
            selectAfterChange(preferred: selection)
        } else if case .personName(let change) = entry {
            refreshPersonNameScopes(from: change.sourceKey, to: change.destinationKey, onlyIfSourceVanished: true)
        } else {
            let continuedTool = viewer && selection == entry.selectionID && (tool == .brush || tool == .spot || tool == .redEye) ? tool : nil
            selectAfterChange(preferred: entry.selectionID)
            if let continuedTool, selection == entry.selectionID { tool = continuedTool }
        }
        switch entry {
        case .edit: status = redo ? "Photo edit redone" : "Photo edit undone"
        case .removeVersion: status = "Version creation undone"
        case .restoreVersion: status = "Version creation redone"
        case .stackPick: status = redo ? "Pick change redone" : "Pick change undone"
        case .captureDates: status = redo ? "Capture date adjustment redone" : "Capture date adjustment undone"
        case .batchMetadata: status = redo ? "Batch metadata change redone" : "Batch metadata change undone"
        case .stamp: status = redo ? "Stamp redone" : "Stamp undone"
        case .locations: status = redo ? "Location change redone" : "Location change undone"
        case .people: status = redo ? "People change redone" : "People change undone"
        case .personName: status = redo ? "Person name change redone" : "Person name change undone"
        case .lightTables: status = redo ? "Light Table change redone" : "Light Table change undone"
        case .browserOrders: status = redo ? "Browser order redone" : "Browser order undone"
        }
    }
    func selectAfterChange(preferred: UUID?) {
        let visible = photos
        let stack = library.photos.first { $0.id == preferred }?.stackID
        selection = visible.first { $0.id == preferred }?.id
            ?? stack.flatMap { id in visible.first { $0.stackID == id }?.id }
            ?? visible.first?.id
        compareOriginal = false; tool = .select
        if comparisonID != nil && comparisonPhotos.count < 2 { stopComparison() }
        if visible.isEmpty { viewer = false }
    }
    var selectedTrashActionIDs: Set<UUID> {
        if batchMode { return Set(photos.map(\.id)).intersection(batchSelection) }
        return selected.map { [$0.id] } ?? []
    }
    func setPhotosTrashed(_ ids: Set<UUID>, trashed: Bool) {
        var draft = library
        let previous = draft.setPhotosTrashed(ids, at: trashed ? Date() : nil)
        guard commitPhotoChanges(draft, previous: previous) else { return }
        batchSelection.subtract(ids)
        selectAfterChange(preferred: selection)
        let description = previous.count == 1 ? "1 photo" : "\(previous.count) photos"
        status = trashed ? "Moved \(description) to Trash" : "Put back \(description)"
    }
    @discardableResult
    func commitPhotoChanges(_ draft: Library, previous: [Photo]) -> Bool {
        guard !previous.isEmpty else { return false }
        var nextHistory = history
        for photo in previous { nextHistory.record(photo) }
        return commit(draft, history: nextHistory)
    }
    func importMetadataPanel() {
        guard !busy, !isViewingTrash else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.xml, UTType(filenameExtension: "xmp") ?? .xml]
        panel.message = "Import XMP, including keyword paths, into the selected photo or match XML records by unique source filename. Supported XML: Isonique photo records and AlbumData.xml metadata."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let records = try MetadataXML.read(url)
            var changes: [(Int, Photo)] = []
            for record in records {
                let id: UUID?
                if let name = record.filename { id = library.metadataTarget(named: name) }
                else { id = selection }
                guard let index = library.photos.firstIndex(where: { $0.id == id && $0.trashedAt == nil }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                changes.append((index, record.applying(to: library.photos[index])))
            }
            var draft = library
            var previous: [Photo] = []
            for (index, photo) in changes where draft.photos[index] != photo {
                previous.append(draft.photos[index]); draft.photos[index] = photo
            }
            if previous.isEmpty || commitPhotoChanges(draft, previous: previous) {
                status = "Imported metadata for \(changes.count) records"
            }
        } catch { self.error = "Metadata import stopped: unsupported, malformed or ambiguous records. " + error.localizedDescription }
    }
    func chooseProofProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let space = CGColorSpace(iccData: data as CFData), space.model == .rgb else { throw CocoaError(.fileReadCorruptFile) }
            proofProfile = data; proofName = url.lastPathComponent; proofEnabled = true
        } catch { self.error = "Choose a valid RGB ICC profile. CMYK printer proofing is not supported." }
    }
    func edit(_ change: (inout Photo) -> Void) {
        guard !busy, !isViewingTrash, let photo = selected else { return }
        var draft = library
        let previous = draft.updatePhotos([photo.id], change: change)
        commitPhotoChanges(draft, previous: previous)
    }
    // Menu and inspector actions share the same rating rules and edit history.
    func adjustRating(by delta: Int) {
        edit { $0.rating = RatingRules.adjusting($0.rating, by: delta) }
    }
    func setRejected(_ rejected: Bool) {
        edit { $0.rating = RatingRules.rejectionRating(isRejected: rejected) }
    }
    func rotate(_ turns: Int) {
        compareOriginal = false; tool = .select
        edit { $0.adjustments.quarterTurns = (($0.adjustments.quarterTurns % 4) + turns + 4) % 4; $0.adjustments.crop = nil }
    }
    func flip(_ axis: FlipAxis) {
        compareOriginal = false; tool = .select
        edit { $0.adjustments.toggleFlip(axis) }
    }
    func showBrowser(allPhotos: Bool = false) {
        viewer = false; tool = .select; compareOriginal = false; stopComparison()
        curveSampling = nil; whiteBalanceSampling = nil; targetedColorSampling = nil
        if allPhotos {
            scope = "all"; search = ""; ratingFilter = .all; originalFilter = .all; colorFilter = .all; advancedSearch = nil
        }
    }
    func exitViewer() {
        if curveSampling != nil || whiteBalanceSampling != nil || targetedColorSampling != nil {
            curveSampling = nil
            whiteBalanceSampling = nil
            targetedColorSampling = nil
            return
        }
        if comparisonID != nil { stopComparison() }
        else { showBrowser() }
    }

    func chooseTool(_ next: EditTool) {
        if next != .select { stopComparison() }
        if next != .spot { spotDraftSource = nil; selectedSpotID = nil; spotPlacement = .source }
        if next != .redEye { selectedRedEyeID = nil }
        viewer = true; compareOriginal = false; tool = next
    }
    func nudgeStraighten(_ delta: Double) {
        edit {
            let angle = StraightenRules.applying(rotation: delta, to: $0.adjustments.straighten)
            guard angle != $0.adjustments.straighten else { return }
            $0.adjustments.straighten = angle
            $0.adjustments.crop = nil
        }
    }
    var canLift: Bool { !busy && !isViewingTrash && selected != nil }

    func lift() {
        guard canLift, let source = selected else { return }
        liftedAdjustments = LiftedSettings(source)
        liftLookupID = nil
        status = "Settings lifted · select another photo and Stamp"
        guard let repository, source.hasUncataloguedIPTC else { return }

        let request = UUID()
        liftLookupID = request
        Task { [weak self] in
            let embedded = await Task.detached(priority: .userInitiated) {
                repository.embeddedIPTC(for: source)
            }.value
            guard let self, self.liftLookupID == request, self.repository === repository else { return }
            self.liftedAdjustments = LiftedSettings(source, embeddedIPTC: embedded)
            self.liftLookupID = nil
        }
    }
    var batchPhotos: [Photo] { library.photos.filter { $0.trashedAt == nil && batchSelection.contains($0.id) } }
    func editBatch(_ change: (inout Photo) -> Void) {
        guard !busy, !isViewingTrash else { return }
        var draft = library
        let previous = draft.updatePhotos(Set(batchPhotos.map(\.id)), change: change)
        if commitPhotoChanges(draft, previous: previous) {
            status = "Updated \(previous.count) photos · Undo restores one photo at a time"
        }
    }
    func stackSelection() {
        guard StackRules.canStack(photoCount: batchPhotos.count) else { return }
        let id = UUID()
        let pick = photos.first { batchSelection.contains($0.id) } ?? batchPhotos.first
        var draft = library
        let previous = draft.updatePhotos(Set(batchPhotos.map(\.id))) { $0.stackID = id }
        if let pick { draft.applyStackPick(StackPickChange(stackID: id, photoID: pick.id, selectionID: pick.id)) }
        if commitPhotoChanges(draft, previous: previous) { status = "Created photo stack" }
    }
    var canStamp: Bool {
        guard let liftedAdjustments, !metadataEditingTargets.isEmpty else { return false }
        if quickPreview && !stampGroups.isEmpty { return false }
        if liftLookupID != nil && stampMetadata.contains(where: { $0.iptcField != nil }) { return false }
        return !stampGroups.isEmpty || stampMetadata.contains(where: liftedAdjustments.includesMetadata)
    }

    func stamp() {
        guard canStamp, let liftedAdjustments else { return }
        let targets = Set(metadataEditingTargets.map(\.id))
        var draft = library
        let previous = draft.stamp(liftedAdjustments, groups: stampGroups, metadata: stampMetadata, onto: targets)
        guard !previous.isEmpty else {
            status = "Selected photos already match the lifted settings"
            return
        }
        var nextHistory = history
        nextHistory.record(.stamp(previous))
        guard commit(draft, history: nextHistory) else { return }
        compareOriginal = false; tool = .select
        if selected == nil { selectAfterChange(preferred: selection) }
        status = previous.count == 1 ? "Stamped settings on 1 photo" : "Stamped settings on \(previous.count) photos"
    }
    func binding<T>(_ path: WritableKeyPath<Photo, T>, fallback: T) -> Binding<T> {
        Binding(get: { self.selected?[keyPath: path] ?? fallback }, set: { value in self.edit { $0[keyPath: path] = value } })
    }
    func addCollection(_ name: String, project: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = Collection(name: trimmed)
        var draft = library
        if project { draft.projects.append(item) } else { draft.albums.append(item) }
        guard commit(draft) else { return }
        scope = project ? "project:\(item.id)" : "album:\(item.id)"
        selection = nil
    }
    @discardableResult
    func renameRegularAlbum(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !trimmed.isEmpty,
              let index = library.albums.firstIndex(where: { $0.id == id && $0.rule == nil }) else { return false }
        if library.albums[index].name == trimmed { return true }
        var draft = library
        draft.albums[index].name = trimmed
        return commit(draft)
    }
    func startSlideshow() {
        guard !importInProgress else { error = "Wait for the import to finish before starting a slideshow."; return }
        guard !busy, !isViewingTrash, repository != nil else { return }
        slideshowPhotos = batchMode ? photos.filter { batchSelection.contains($0.id) } : photos
        showSlideshow = !slideshowPhotos.isEmpty
    }
    func importPanel() {
        guard !busy, repository != nil else { return }
        let panel = NSOpenPanel(); panel.title = "Import photographs"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        pendingDeviceImport = nil; pendingImport = panel.urls; showImportOptions = true
    }
    func showImportSettings() {
        pendingImport = []; pendingDeviceImport = nil; showImportOptions = true
    }

    func importDevicePanel() {
        guard !busy, repository != nil else { return }
        pendingImport = []; pendingDeviceImport = nil
        cameraDiscovery.start()
        showDeviceImport = true
    }

    func finishDevicePicker() {
        if pendingDeviceImport != nil { showImportOptions = true }
        else { cameraDiscovery.stop() }
    }

    func finishImportOptions() {
        if !importInProgress {
            pendingDeviceImport?.close()
            cameraDiscovery.stop()
        }
        pendingImport = []; pendingDeviceImport = nil
    }

    func importURLs(_ urls: [URL], options: ImportOptions = ImportOptions(), newProjectName: String? = nil,
                    device: DeviceImportSelection? = nil) {
        guard !busy, let repository else { return }
        if case .camera(let session, _, _) = device, !cameraDiscovery.cameras.contains(where: { $0 === session.camera }) {
            error = DeviceImportError.disconnected.localizedDescription
            return
        }
        busy = true; importInProgress = true; status = "Importing originals…"
        let initialLibrary = library
        let projectID = library.projects.first(where: { scope == "project:\($0.id)" })?.id
        let albumID = library.albums.first(where: { $0.rule == nil && scope == "album:\($0.id)" })?.id
        let task = Task.detached(priority: .userInitiated) {
            var draft = initialLibrary
            let report: ImportReport
            let progress: (ImportProgress) async -> Void = { await self.reportImportProgress($0) }
            switch device {
            case .memoryCard(let card, let files):
                report = await ImportJob.run(memoryCard: card, selectedFiles: files, options: options, repository: repository,
                    projectID: projectID, albumID: albumID, newProjectName: newProjectName, into: &draft, progress: progress)
            case .camera(let session, let catalogue, let selected):
                report = await ImportJob.run(cameraFiles: catalogue, selectedPhotos: selected, options: options, repository: repository,
                    projectID: projectID, albumID: albumID, newProjectName: newProjectName, into: &draft, download: { file, destination in
                        try await session.download(file, to: destination)
                    }, progress: progress)
                await session.close()
            case nil:
                report = await ImportJob.run(urls: urls, options: options, repository: repository, projectID: projectID,
                    albumID: albumID, newProjectName: newProjectName, into: &draft, progress: progress)
            }
            return (draft, report)
        }
        importTask = task
        Task {
            let (draft, report) = await task.value
            library = draft
            if let project = report.createdProject {
                showBrowser(allPhotos: true)
                scope = "project:\(project)"
            }
            selection = report.selection ?? selection
            importTask = nil; importProgress = nil; cancellingImport = false
            importInProgress = false; busy = false
            if device != nil { cameraDiscovery.stop() }
            let prefix = report.cancelled ? "Import cancelled · " : ""
            status = prefix + "Imported \(report.imported) · duplicates \(report.duplicates) · failed \(report.errors.count)"
            if !report.errors.isEmpty { error = report.errors.prefix(8).joined(separator: "\n") }
        }
    }

    private func reportImportProgress(_ progress: ImportProgress) {
        if !cancellingImport { importProgress = progress }
    }

    func cancelImport() {
        guard let importTask, !cancellingImport else { return }
        cancellingImport = true
        importTask.cancel()
    }
    func recoverPanel() {
        guard let repository, !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Recover originals from an Aperture library"
        panel.message = "A verified temporary copy is made first. Embedded Masters/Originals and any captions, keywords and ratings embedded in those files are recovered; legacy albums, adjustments and referenced originals are not migrated. Allow enough free space for a complete copy."
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        busy = true; status = "Copying and verifying legacy library…"
        var snapshot = library
        Task {
            let result = await Task.detached { () -> (Library, String, String?) in
                do {
                    let counts = try repository.recoverLegacy(source, into: &snapshot)
                    let details = counts.unsupported.isEmpty ? nil : "Unsupported originals (first 20):\n" + counts.unsupported.prefix(20).joined(separator: "\n")
                    return (snapshot, "Recovered \(counts.imported) · duplicates \(counts.duplicates) · unsupported \(counts.unsupported.count) · source integrity verified", details)
                } catch { return (snapshot, "Recovery stopped", error.localizedDescription) }
            }.value
            library = result.0; status = result.1; error = result.2; busy = false
        }
    }
    func exportPanel() { if !isViewingTrash, (batchMode ? !batchPhotos.isEmpty : selected != nil) && !busy { showExportOptions = true } }
    func exportWithOptions(_ options: ExportOptions, batchPlan: BatchExport.Plan?) {
        guard !isViewingTrash else { return }
        if let batchPlan { exportBatch(batchPlan); return }
        guard !batchMode, let photo = selected, let repository, !busy else { return }
        let panel = NSSavePanel()
        let suffix = options.format == .original ? (photo.filename as NSString).pathExtension : options.format.suffix
        panel.allowedContentTypes = options.format == .original ? [UTType(filenameExtension: suffix) ?? .data] : [options.format.type]
        let base = photo.exportBaseName + (options.format == .original ? "-original" : "-edited")
        panel.nameFieldStringValue = suffix.isEmpty ? base : base + "." + suffix
        panel.message = options.format == .original ? "Copies the unchanged original with its embedded metadata." : "Exports with adjustments and your selected metadata."
        if options.xmpSidecar == true { panel.message += " A matching XMP sidecar will be saved alongside the image." }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = "Rendering full-resolution export…"
        Task {
            let result = await Task.detached { () -> String? in
                do { try Renderer.export(photo, repository: repository, to: url, options: options); return nil }
                catch { return error.localizedDescription }
            }.value
            busy = false; error = result; status = result == nil ? "Exported \(url.lastPathComponent)" : "Export failed"
        }
    }
}

@main struct IsoniqueApp: App {
    @StateObject private var workspace: Workspace
    @Environment(\.openWindow) private var openWindow

    init() {
        AppPreferencesMigration.migrateForCurrentApp()
        _workspace = StateObject(wrappedValue: Workspace())
    }

    var body: some Scene {
        WindowGroup("Isonique") {
            ContentView().environmentObject(workspace)
                .frame(minWidth: 1050, minHeight: 650)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    WindowScreenshot.shared.startIfRequested()
                    // An optional launch probe records a real ordered, visible AppKit window.
                    if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--launch-report"), ProcessInfo.processInfo.arguments.indices.contains(i + 1) {
                        let path = ProcessInfo.processInfo.arguments[i + 1]
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            let windows = NSApplication.shared.windows.filter { $0.isVisible && $0.frame.width >= 1000 }
                            let report = "architecture=\(ProcessInfo.processInfo.machineArchitecture)\nvisibleWindows=\(windows.count)\ntitle=\(windows.first?.title ?? "")\n"
                            try? report.write(toFile: path, atomically: true, encoding: .utf8)
                        }
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Isonique") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Isonique",
                        .credits: NSAttributedString(string: "Independent, open-source photo management and editing."),
                    ])
                }
            }
            CommandGroup(after: .toolbar) {
                Menu("Photography Workspace") {
                    ForEach(PhotographyWorkspaceMode.allCases) { mode in
                        Button {
                            workspace.performPhotographyWorkspaceCommand(.selectMode(mode))
                        } label: {
                            if workspace.photographyMode == mode { Label(mode.rawValue, systemImage: "checkmark") }
                            else { Text(mode.rawValue) }
                        }
                    }
                }
                Button(workspace.isPhotographyFullScreen ? "Exit Photography Full Screen" : "Enter Photography Full Screen") {
                    workspace.togglePhotographyFullScreen()
                }
                Button(workspace.photographyLayout.browser ? "Hide Browser" : "Show Browser") {
                    workspace.performPhotographyWorkspaceCommand(.togglePanel(.browser))
                }
                Button(workspace.photographyLayout.filmstrip ? "Hide Filmstrip" : "Show Filmstrip") {
                    workspace.performPhotographyWorkspaceCommand(.togglePanel(.filmstrip))
                }
                Button(workspace.photographyLayout.inspector ? "Hide Inspector" : "Show Inspector") {
                    workspace.performPhotographyWorkspaceCommand(.togglePanel(.inspector))
                }
                Button(workspace.photographyLayout.toolbar ? "Hide Toolbar" : "Show Toolbar") {
                    workspace.performPhotographyWorkspaceCommand(.togglePanel(.toolbar))
                }
                Button("Cycle Photography Panels") {
                    workspace.performPhotographyWorkspaceCommand(.cycleFocus)
                }
                Button(workspace.secondaryViewerVisible ? "Close Secondary Display Viewer" : "Show Secondary Display Viewer") {
                    workspace.toggleSecondaryViewer()
                }.disabled(!workspace.secondaryViewerAvailable)
                Button("Customize Toolbar…") { workspace.showToolbarEditor = true }
                Button("Keyboard Command Editor…") { workspace.showCommandEditor = true }
                Divider()
                ForEach(BrowserPresentation.allCases) { presentation in
                    Button(presentation.rawValue) { workspace.choosePresentation(presentation) }
                        .disabled(!workspace.canChoosePresentation(presentation))
                }
                GridThumbnailSizePicker(model: workspace)
                Toggle("Quick Preview", isOn: Binding(get: { workspace.quickPreview }, set: workspace.setQuickPreview))
                    .disabled(!workspace.quickPreview && !workspace.canToggleQuickPreview)
                Button("People", action: workspace.showPeople)
                Toggle("Second Browser", isOn: Binding(get: { workspace.secondaryBrowser.visible },
                    set: workspace.setSecondaryBrowserVisible))
                    .disabled(!workspace.secondaryBrowser.visible && !workspace.canShowSecondaryBrowser)
                Button("Customize List Columns…") { workspace.showListColumnEditor = true }
                    .disabled(workspace.browserLayout != .list)
                Button("Reset List Columns", action: workspace.resetListColumns)
                    .disabled(workspace.browserLayout != .list)
                Toggle("Show Keyword Controls", isOn: $workspace.showKeywordControls)
                Divider()
                Button("Advanced Search…") { workspace.showAdvancedSearch = true }
                    .disabled(workspace.busy || workspace.repository == nil)
                Button("Clear Advanced Search") { workspace.advancedSearch = nil }
                    .disabled(workspace.advancedSearch == nil || workspace.busy)
                Divider()
                Button("Compare Photos", action: workspace.startComparison)
                    .disabled(!workspace.canStartComparison)
                Button("End Comparison", action: workspace.stopComparison)
                    .disabled(workspace.comparisonID == nil)
                Button("Promote Compare Select", action: workspace.promoteComparisonSelection)
                    .disabled(!workspace.canPromoteComparisonSelection)
                Button("Remove Compare Select", action: workspace.removeComparisonSelection)
                    .disabled(!workspace.canRemoveComparisonSelection)
                Divider()
                Toggle("Highlight Hot & Cold Areas", isOn: $workspace.clipping.both)
                Toggle("Highlight Clipping Warning", isOn: $workspace.clipping.highlights)
                Toggle("Shadow Clipping Warning", isOn: $workspace.clipping.shadows)
                Divider()
                Button(workspace.loupeActive ? "Hide Loupe" : "Show Loupe", action: workspace.toggleLoupe)
                    .disabled(!workspace.loupeActive && !workspace.canShowLoupe)
            }
            CommandMenu("Review") {
                Button("New Light Table from Selection", action: workspace.createLightTable)
                    .disabled(!workspace.canCreateLightTable)
                Button("Auto Stack by Capture Time…") { workspace.showAutoStack = true }.disabled(workspace.busy || workspace.isViewingTrash || workspace.photos.isEmpty)
                Button("Start Slideshow…") {
                    workspace.startSlideshow()
                }.disabled(workspace.busy || workspace.isViewingTrash || workspace.photos.isEmpty || workspace.repository == nil)
            }
            CommandMenu("Photos") {
                Button("Dodge Brush") { workspace.chooseBrush(.dodge) }.disabled(!workspace.canBrush)
                Button("Burn Brush") { workspace.chooseBrush(.burn) }.disabled(!workspace.canBrush)
                Button("Saturation Brush") { workspace.chooseBrush(.saturation) }.disabled(!workspace.canBrush)
                Button("Definition Brush") { workspace.chooseBrush(.definition) }.disabled(!workspace.canBrush)
                Button("Sharpening Brush") { workspace.chooseBrush(.sharpening) }.disabled(!workspace.canBrush)
                Button("Luminance Noise Reduction Brush") { workspace.chooseBrush(.noiseReduction) }
                    .disabled(!workspace.canBrush)
                Button("Contrast Brush") { workspace.chooseBrush(.contrast) }.disabled(!workspace.canBrush)
                Button("Blur Brush") { workspace.chooseBrush(.blur) }.disabled(!workspace.canBrush)
                Button("Tint Brush") { workspace.chooseBrush(.tint) }.disabled(!workspace.canBrush)
                Button("Skin Smoothing Brush") { workspace.chooseBrush(.skinSmoothing) }.disabled(!workspace.canBrush)
                Button("Polarize Brush") { workspace.chooseBrush(.polarize) }.disabled(!workspace.canBrush)
                Button("Halo Reduction Brush") { workspace.chooseBrush(.haloReduction) }.disabled(!workspace.canBrush)
                Button("Repair Spot") { workspace.chooseSpotRemoval(.repair) }.disabled(!workspace.canSpotRemove)
                Button("Clone Spot") { workspace.chooseSpotRemoval(.clone) }.disabled(!workspace.canSpotRemove)
                Button("Manual Red-Eye") { workspace.chooseRedEyeCorrection() }.disabled(!workspace.canCorrectRedEye)
                Divider()
                Menu("Apply Custom Adjustment Preset") {
                    ForEach(workspace.adjustmentPresets) { preset in
                        Button(preset.name) { workspace.previewAdjustmentPreset(preset) }
                    }
                }.disabled(workspace.quickPreview || workspace.adjustmentPresets.isEmpty || workspace.selected == nil)
                Button("Manage Adjustment Presets…") { workspace.showAdjustmentPresetManager = true }
                    .disabled(workspace.selected == nil)
                Divider()
                Button("Lift Settings", action: workspace.lift)
                    .disabled(!workspace.canLift)
                Button("Stamp Selected Settings", action: workspace.stamp)
                    .disabled(!workspace.canStamp)
                Divider()
                Button("New Version from Original") { workspace.createVersion(from: .original) }
                    .disabled(!workspace.canCreateVersion)
                Button("Duplicate Version") { workspace.createVersion(from: .current) }
                    .disabled(!workspace.canCreateVersion)
                Button("Edit with External Editor…") { workspace.editWithExternalEditor() }
                    .disabled(!workspace.canEditExternally)
                Divider()
                ForEach(FlipAxis.allCases) { axis in
                    Button(axis.rawValue) { workspace.flip(axis) }
                        .disabled(workspace.busy || workspace.isViewingTrash || workspace.quickPreview || workspace.selected == nil)
                }
            }
            CommandMenu("Stacks") {
                Button("Stack Selected", action: workspace.stackSelection)
                    .keyboardShortcut("k").disabled(workspace.busy || !workspace.batchMode || !StackRules.canStack(photoCount: workspace.batchPhotos.count))
                Divider()
                Button("Set Stack Pick") { workspace.setStackPick() }
                    .keyboardShortcut("\\").disabled(!workspace.canSetStackPick)
                Button(workspace.selectedIsAlbumPick ? "Clear Album Pick" : "Set Album Pick") {
                    workspace.setStackPick(inAlbum: true)
                }.keyboardShortcut("\\", modifiers: [.command, .shift]).disabled(!workspace.canSetAlbumPick)
                Divider()
                Button(workspace.selectedStackIsCollapsed ? "Expand Stack" : "Collapse Stack") {
                    if let stackID = workspace.selected?.stackID { workspace.toggleStack(stackID) }
                }.disabled(!workspace.canToggleSelectedStack)
            }
            CommandMenu("Metadata") {
                PeopleCommands(model: workspace)
                Divider()
                Button("Keyword Vocabulary…") { workspace.showKeywordVocabulary = true }
                Button("Manage Keyword Groups…") { workspace.showKeywordGroupEditor = true }
                if let group = workspace.keywordGroups.active {
                    Menu("Add Keyword") {
                        ForEach(group.keywords, id: \.self) { keyword in
                            Button(keyword) { workspace.addKeywords(keyword) }
                        }
                        Divider()
                        Button("Apply Group") { workspace.addKeywords(group.keywordText) }
                    }
                    .disabled(!workspace.canOpenBatchMetadata)
                    Menu("Remove Keyword") {
                        ForEach(group.keywords, id: \.self) { keyword in
                            Button(keyword) { workspace.removeKeywords(keyword) }
                        }
                    }
                    .disabled(!workspace.canOpenBatchMetadata)
                }
                Divider()
                Button("Batch Change…", action: workspace.openBatchMetadata)
                    .disabled(!workspace.canOpenBatchMetadata)
                Button("Catalogue IPTC from Originals…", action: workspace.openInheritedIPTCReview)
                    .disabled(!workspace.canReviewInheritedIPTC)
                if let scan = workspace.inheritedIPTCScan {
                    Button("Cancel IPTC Review") { scan.cancel() }.disabled(scan.isCancelled)
                }
                Button("Catalogue EXIF from Originals") { workspace.catalogueSelected(.exif) }
                    .disabled(!workspace.canCatalogueSelected(.exif))
                Button("Catalogue GPS from Originals") { workspace.catalogueSelected(.gps) }
                    .disabled(!workspace.canCatalogueSelected(.gps))
                if let scan = workspace.originalMetadataCatalogueTask {
                    Button("Cancel Metadata Cataloguing") { scan.cancel() }.disabled(scan.isCancelled)
                }
                PhotoLocationCommands(model: workspace)
                Button("Adjust Date and Time…", action: workspace.openCaptureDateCorrection)
                    .disabled(!workspace.canAdjustCaptureDate)
                Divider()
                Button("Clear Color Label") { workspace.setColorLabel(nil) }
                    .keyboardShortcut("0").disabled(!workspace.canReviewSelection)
                ForEach(PhotoColorLabel.allCases) { label in
                    Button("Set Color Label to \(workspace.name(for: label))") { workspace.setColorLabel(label) }
                        .keyboardShortcut(KeyEquivalent(Character(String(label.rawValue))))
                        .disabled(!workspace.canReviewSelection)
                }
                Divider()
                Button("Flag or Unflag Photos", action: workspace.toggleReviewFlag).disabled(!workspace.canReviewSelection)
            }
            CommandMenu("Rating") {
                ForEach(0...5, id: \.self) { rating in
                    Button(rating == 0 ? "Set Unrated" : "Set \(rating) Stars") { workspace.setReviewRating(rating) }
                        .disabled(!workspace.canReviewSelection)
                }
                Button("Reject Photos") { workspace.setReviewRating(RatingRules.rejected) }.disabled(!workspace.canReviewSelection)
                Divider()
                Button("Raise Rating") { workspace.adjustReviewRating(by: 1) }
                    .disabled(!workspace.canReviewSelection || (!workspace.batchMode && (workspace.reviewSelected?.rating ?? RatingRules.maximum) >= RatingRules.maximum))
                Button("Lower Rating") { workspace.adjustReviewRating(by: -1) }
                    .disabled(!workspace.canReviewSelection || (!workspace.batchMode && (workspace.reviewSelected?.rating ?? RatingRules.rejected) <= RatingRules.rejected))
            }
            CommandGroup(replacing: .help) {
                Button("Features & Limits…") { openWindow(id: "features") }
            }
            CommandGroup(replacing: .printItem) {
                if let lightTable = workspace.activeLightTable {
                    Button("Print Light Table…") { workspace.printLightTable(lightTable) }
                        .keyboardShortcut("p")
                        .disabled(lightTable.items.isEmpty || workspace.busy)
                } else {
                    Button("Print Contact Sheet…", action: workspace.openPrintLayout)
                        .keyboardShortcut("p")
                        .disabled(!workspace.canPrintPhotos)
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button(workspace.activeLightTable == nil ? "Undo Photo Edit" : "Undo Light Table Change") {
                    workspace.undoEdit()
                }.keyboardShortcut("z").disabled(!workspace.canUndo || workspace.busy)
                Button(workspace.activeLightTable == nil ? "Redo Photo Edit" : "Redo Light Table Change") {
                    workspace.redoEdit()
                }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.canRedo || workspace.busy)
            }
            CommandGroup(after: .newItem) {
                Button("New Light Table from Selection", action: workspace.createLightTable)
                    .disabled(!workspace.canCreateLightTable)
                Button("New Smart Album…") { workspace.editingSmartAlbum = nil; workspace.showSmartAlbum = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(workspace.busy || workspace.repository == nil)
                Button("Import Photos…", action: workspace.importPanel).keyboardShortcut("i").disabled(workspace.busy || workspace.repository == nil)
                Button("Import from Camera or Card…", action: workspace.importDevicePanel)
                    .disabled(workspace.busy || workspace.repository == nil)
                Button("Tethered Capture…") { workspace.tetherCaptureSource = .camera }
                    .disabled(workspace.busy || workspace.repository == nil)
                if ProcessInfo.processInfo.arguments.contains("--simulate-tether") {
                    Button("Simulated Tethered Capture…") { workspace.tetherCaptureSource = .simulated }
                        .disabled(workspace.busy || workspace.repository == nil)
                }
                if workspace.importInProgress {
                    Button("Cancel Import", action: workspace.cancelImport).disabled(workspace.cancellingImport)
                }
                Button("Import Project Library…", action: workspace.importProjectLibraryPanel)
                    .disabled(workspace.busy || workspace.repository == nil)
                if let task = workspace.projectImportTask {
                    Button("Cancel Project Import", action: workspace.cancelProjectImport)
                        .disabled(task.isCancelled)
                }
                Button("Merge Project Library…", action: workspace.mergeProjectLibraryPanel)
                    .disabled(workspace.busy || workspace.repository == nil)
                if let task = workspace.projectMergeTask {
                    Button("Cancel Project Merge", action: workspace.cancelProjectMerge)
                        .disabled(task.isCancelled)
                }
                Button("Merge Libraries…", action: workspace.mergeLibrariesPanel)
                    .disabled(workspace.busy || workspace.repository == nil)
                if let task = workspace.libraryMergeTask {
                    Button("Cancel Library Merge") { task.cancel() }.disabled(task.isCancelled)
                }
                Button("Import XML / XMP Metadata…", action: workspace.importMetadataPanel)
                    .disabled(workspace.busy || workspace.isViewingTrash || workspace.library.activePhotos.isEmpty)
                Button("Import & History Options…", action: workspace.showImportSettings).disabled(workspace.busy)
                Divider()
                Button("New Isonique Library…", action: workspace.createLibraryPanel).keyboardShortcut("n", modifiers: [.command, .shift]).disabled(workspace.busy)
                Button("Open Isonique Library…", action: workspace.openLibraryPanel).disabled(workspace.busy)
                Menu("Open Recent Library") {
                    ForEach(workspace.recentLibraryPaths, id: \.self) { path in
                        Button(workspace.recentLibraryTitle(for: path)) {
                            Task { await workspace.openLibrary(at: URL(fileURLWithPath: path, isDirectory: true)) }
                        }.disabled(path == workspace.repository?.root.path)
                    }
                    Divider()
                    Button("Clear Recent Libraries") { workspace.recentLibraryPaths = [] }
                }.disabled(workspace.busy || workspace.recentLibraryPaths.isEmpty)
                Button("Reload Library") { Task { await workspace.reloadLibrary() } }
                    .disabled(workspace.busy || workspace.repository == nil)
                Button("Export Project as Library…") {
                    if let project = workspace.selectedProject { workspace.exportProjectPanel(project) }
                }.disabled(workspace.busy || workspace.repository == nil || workspace.selectedProject == nil)
                if let task = workspace.projectExportTask {
                    Button("Cancel Project Export") { task.cancel() }
                }
                Button("Back Up Library…", action: workspace.backupLibraryPanel).disabled(workspace.busy || workspace.repository == nil)
                Button("Check Library Integrity", action: workspace.verifyLibrary).disabled(workspace.busy || workspace.repository == nil)
                Button("Library First Aid…", action: workspace.showLibraryFirstAid).disabled(workspace.busy || workspace.repository == nil)
                Button("Relink Original…") {
                    if let photo = workspace.selected { workspace.relinkOriginalPanel(photo) }
                }.disabled(workspace.busy || workspace.isViewingTrash || !workspace.canRelinkSelectedOriginal)
                Button("Reconnect Referenced Originals…") { workspace.findOriginalsPanel(.reconnect) }
                    .disabled(!workspace.canFindOriginals(.reconnect))
                Button("Recover Missing Managed Originals…") { workspace.findOriginalsPanel(.recoverManaged) }
                    .disabled(!workspace.canFindOriginals(.recoverManaged))
                if let task = workspace.originalJobTask {
                    Button("Cancel Original Operation") { task.cancel() }
                }
                Button("Consolidate Original") {
                    if let photo = workspace.selected { workspace.consolidateOriginal(photo) }
                }.disabled(workspace.busy || workspace.isViewingTrash || workspace.selected?.referencedPath == nil)
                Button("Consolidate Selected Originals") {
                    Task { await workspace.consolidateSelectedOriginals() }
                }.disabled(!workspace.canConsolidateSelectedOriginals)
                Button("Relocate Originals…", action: workspace.relocateSelectedOriginalsPanel)
                    .disabled(!workspace.canRelocateSelectedOriginals)
                Button("Refresh Original Status", action: workspace.refreshOriginalStatus).disabled(workspace.busy || workspace.repository == nil)
                Button("Restore Library Backup…", action: workspace.restoreLibraryPanel).disabled(workspace.busy)
                Button("Recover Aperture Originals…", action: workspace.recoverPanel).disabled(workspace.busy || workspace.repository == nil)
                Button("Export Photos…", action: workspace.exportPanel).keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(workspace.isViewingTrash || (workspace.batchMode ? workspace.batchPhotos.isEmpty : workspace.selected == nil) || workspace.busy)
                Divider()
                Button(workspace.isViewingTrash ? "Put Back Photos" : "Move Photos to Trash") {
                    workspace.setPhotosTrashed(workspace.selectedTrashActionIDs, trashed: !workspace.isViewingTrash)
                }.keyboardShortcut(.delete, modifiers: [.command]).disabled(workspace.busy || workspace.selectedTrashActionIDs.isEmpty)
                Button("Empty Library Trash…", action: workspace.showEmptyLibraryTrashReview)
                    .disabled(!workspace.canReviewEmptyLibraryTrash)
            }
        }
        Window("Features & Limits", id: "features") {
            FeatureGuide().preferredColorScheme(.dark)
        }
        .defaultSize(width: 720, height: 700)
        Settings {
            ReviewSettingsView().environmentObject(workspace).preferredColorScheme(.dark)
        }
    }
}
extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "other"
        #endif
    }
}
// System Liquid Glass on macOS 26+, with native vibrancy on older systems.
private struct WorkspaceGlass: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.12)))
        }
    }
}
private extension View {
    func workspaceGlass(radius: CGFloat = 16) -> some View { modifier(WorkspaceGlass(radius: radius)) }
}

private enum CollectionEditor: Identifiable {
    case newProject, newAlbum, renameAlbum(Collection)

    var id: String {
        switch self {
        case .newProject: return "newProject"
        case .newAlbum: return "newAlbum"
        case .renameAlbum(let album): return album.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .newProject: return "New Project"
        case .newAlbum: return "New Album"
        case .renameAlbum: return "Rename Album"
        }
    }
}

private struct CollectionNameSheet: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let editor: CollectionEditor

    init(_ editor: CollectionEditor) {
        self.editor = editor
        if case .renameAlbum(let album) = editor { _name = State(initialValue: album.name) }
        else { _name = State(initialValue: "") }
    }

    private var actionTitle: String {
        if case .renameAlbum = editor { return "Rename" }
        return "Create"
    }

    private var validName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editor.title).font(.title2)
            TextField("Name", text: $name).frame(width: 320).onSubmit(save)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle, action: save).buttonStyle(.borderedProminent).disabled(!validName)
            }
        }.padding(28)
    }

    private func save() {
        guard validName else { return }
        switch editor {
        case .newProject: model.addCollection(name, project: true)
        case .newAlbum: model.addCollection(name, project: false)
        case .renameAlbum(let album):
            guard model.renameRegularAlbum(album.id, to: name) else { return }
        }
        dismiss()
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.openWindow) private var openWindow
    @State private var collectionEditor: CollectionEditor?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @FocusState private var focusedPhotographyPanel: PhotographyWorkspaceFocus?
    private static let welcomeIcon: NSImage = Bundle.main.url(forResource: "Isonique", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:)) ?? NSApplication.shared.applicationIconImage

    private var workspaceView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("I")
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .workspaceGlass(radius: 14)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) { Text("Isonique").font(.system(size: 22, weight: .semibold, design: .rounded)); Text("PHOTO WORKSPACE").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary) }
                }.padding(20)
                let stacks = model.activeStacks
                List(selection: $model.scope) {
                    Section("Library") {
                        Label("All Photos", systemImage: "photo.on.rectangle.angled").tag("all").simultaneousGesture(TapGesture().onEnded { model.showBrowser(allPhotos: true) })
                        Label("Flagged", systemImage: "flag").tag("flagged")
                        Label("People", systemImage: "person.crop.rectangle").tag("people-gallery")
                            .contextMenu {
                                Button("People Review Summary…") { model.openPeopleSummary(.library) }
                                Button("Show Photos with Faces", action: model.showFacePhotos)
                                Button("Review Unnamed Faces…") { model.openUnnamedFaces(.library) }
                                    .disabled(!model.canOpenUnnamedFaces)
                            }
                        Label("Trash", systemImage: "trash").tag("trash")
                    }
                    let people = model.peopleGroups
                    if !people.isEmpty {
                        Section("Named People") {
                            ForEach(people) { person in
                                Label("\(person.name) (\(person.photoCount))", systemImage: "person")
                                    .tag(person.scope)
                                    .contextMenu {
                                        Button("Person Overview…") { model.openPersonOverview(person) }
                                            .disabled(model.busy)
                                        Button("Rename or Merge Person…") { model.openPersonNameEditor(person) }
                                            .disabled(model.busy)
                                    }
                            }
                        }
                    }
                    Section("Projects") {
                        ForEach(model.library.projects) { project in
                            Label(project.name, systemImage: "folder")
                                .tag("project:\(project.id)")
                                .contextMenu {
                                    Button("People Review Summary…") { model.openPeopleSummary(.project(project.id)) }
                                    Button("Review Unnamed Faces…") { model.openUnnamedFaces(.project(project.id)) }
                                        .disabled(!model.canOpenUnnamedFaces)
                                    Button("Export Project as Library…") { model.exportProjectPanel(project) }
                                        .disabled(model.busy || model.repository == nil)
                                }
                        }
                    }
                    Section("Stacks") {
                        ForEach(stacks.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                            let members = stacks[id] ?? []
                            let pick = model.library.stackBrowser?.preferredPick(stackID: id, albumID: nil, members: members) ?? members.first
                            Label(pick?.displayName ?? "Stack", systemImage: "square.3.layers.3d").tag("stack:\(id)")
                        }
                    }
                    Section("Albums") {
                        ForEach(model.library.albums) { album in Label(album.name, systemImage: album.rule == nil ? "rectangle.stack" : "gearshape.2").tag("album:\(album.id)")
                            .contextMenu {
                                if album.rule != nil {
                                    Button("Edit Smart Album…") { model.editingSmartAlbum = album.id; model.showSmartAlbum = true }
                                        .disabled(model.busy)
                                } else {
                                    Button("Rename Album…") {
                                        collectionEditor = .renameAlbum(album)
                                    }.disabled(model.busy)
                                }
                            } }
                    }
                    Section("Light Tables") {
                        ForEach(model.lightTables) { layout in
                            Label(layout.name, systemImage: "rectangle.on.rectangle.angled")
                                .tag("lightTable:\(layout.id)")
                                .contextMenu {
                                    Button("Add Visible Selection") { model.addSelection(toLightTable: layout.id) }
                                        .disabled(model.lightTableCandidatePhotos.isEmpty)
                                    Button("Duplicate Light Table") { model.duplicateLightTable(layout.id) }
                                    Button("Delete Light Table", role: .destructive) {
                                        model.deleteLightTable(layout.id)
                                    }
                                }
                        }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                HStack {
                    Menu {
                        Button("New Project") { collectionEditor = .newProject }
                        Button("New Album") { collectionEditor = .newAlbum }
                        Button("New Smart Album…") { model.editingSmartAlbum = nil; model.showSmartAlbum = true }
                        Button("New Light Table from Selection", action: model.createLightTable)
                            .disabled(!model.canCreateLightTable)
                    } label: { Image(systemName: "plus"); Text("Create") }
                        .menuStyle(.borderlessButton)
                    Spacer()
                    Text("\(model.library.activePhotos.count) photos").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.background(.ultraThinMaterial).navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if model.photographyLayout.toolbar { HStack {
                    if model.viewer {
                        Button { model.showBrowser() } label: { Label("Back to \(model.title)", systemImage: "chevron.left") }
                            .help("Return to the Browser; Escape also goes back")
                        if model.scope != "all" || !model.search.isEmpty || model.ratingFilter != .all || model.originalFilter != .all || model.colorFilter != .all || model.advancedSearch != nil {
                            Button("All Photos") { model.showBrowser(allPhotos: true) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.title).font(.title2.weight(.semibold))
                        if !model.isPeopleGallery {
                            Text("\(model.activeLightTable?.items.count ?? model.photos.count) photographs")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if model.scope == "people" || model.isPeopleGallery {
                        Button("Unnamed Faces…") { model.openUnnamedFaces(.library) }
                            .disabled(!model.canOpenUnnamedFaces)
                    }
                    if model.isPeopleGallery {
                        Button("Photos with Faces", action: model.showFacePhotos)
                    }
                    if let person = model.selectedPersonGroup {
                        Button("Person Overview…") { model.openPersonOverview(person) }
                            .disabled(model.busy)
                    }
                    if model.activeLightTable == nil, model.advancedSearch != nil, !model.isPeopleGallery {
                        Button("Clear Advanced Search", systemImage: "xmark.circle") { model.advancedSearch = nil }
                            .labelStyle(.iconOnly).help("Clear Advanced Search")
                    }
                    if model.activeLightTable == nil, model.isViewingTrash {
                        Button("Put Back") { model.setPhotosTrashed(model.selectedTrashActionIDs, trashed: false) }
                            .disabled(model.selectedTrashActionIDs.isEmpty)
                        Button("Empty Trash…", action: model.showEmptyLibraryTrashReview)
                            .disabled(!model.canReviewEmptyLibraryTrash)
                    }
                    if model.activeLightTable == nil, !model.isPeopleGallery {
                        Picker("Rating filter", selection: $model.ratingFilter) { ForEach(RatingFilter.allCases) { filter in Text(filter.label).tag(filter) } }.labelsHidden().frame(width: 165)
                        Picker("View", selection: Binding(get: { model.presentation }, set: model.choosePresentation)) {
                            ForEach(BrowserPresentation.allCases) { presentation in
                                Image(systemName: presentation.icon).accessibilityLabel(presentation.rawValue).tag(presentation)
                                    .disabled(!model.canChoosePresentation(presentation))
                            }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 155)
                        Button(action: model.toggleQuickPreview) {
                            Image(systemName: model.quickPreview ? "bolt.fill" : "bolt")
                                .foregroundStyle(model.quickPreview ? Color.yellow : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help(model.quickPreview ? "Turn Off Quick Preview" : "Turn On Quick Preview")
                        .accessibilityLabel(model.quickPreview ? "Turn Off Quick Preview" : "Turn On Quick Preview")
                        .disabled(!model.quickPreview && !model.canToggleQuickPreview)
                    }
                }.padding(.horizontal, 22).padding(.vertical, 16)
                    .focusable().focusEffectDisabled()
                    .focused($focusedPhotographyPanel, equals: .toolbar)
                Divider().opacity(0.4) }
                if model.activeLightTable == nil, model.photographyLayout.toolbar, !model.isPeopleGallery {
                    if model.batchMode { BatchBar() }
                    if model.showKeywordControls && !model.isViewingTrash { KeywordControls() }
                    if !model.isViewingTrash { EditBar().disabled(model.batchMode || model.quickPreview) }
                    Divider().opacity(0.4)
                }
                HSplitView {
                    if model.activeLightTable == nil, model.viewer, model.photographyLayout.browser {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(model.photos) { photo in
                                    photoCell(photo, compact: true, photographyFocus: .browser)
                                }
                            }.padding(10)
                        }
                        .frame(minWidth: 126, idealWidth: 146, maxWidth: 180)
                        .background(Color(white: 0.04))
                        .focusable().focusEffectDisabled()
                        .focused($focusedPhotographyPanel, equals: .browser)
                        .accessibilityLabel("Photography Browser")
                    }
                    VStack(spacing: 0) {
                        if let lightTable = model.activeLightTable {
                            LightTableWorkspace(layout: lightTable).environmentObject(model)
                        } else if model.isPeopleGallery {
                            PeopleGalleryView().environmentObject(model)
                        } else if model.presentation == .places {
                            PlacesBrowser(model: model) { photo, onSelect in
                                photoCell(photo, compact: true, onSelect: onSelect)
                            }
                        } else if model.photos.isEmpty, model.scope == "people" {
                            ContentUnavailableView("No Faces in This View", systemImage: "person.crop.rectangle",
                                description: Text("Select photos in the Browser, then choose Metadata → Detect Faces in Selection."))
                        } else if model.photos.isEmpty {
                            VStack(spacing: 18) {
                                Image(nsImage: Self.welcomeIcon)
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .accessibilityHidden(true)
                                if model.isViewingTrash {
                                    Text("No matching photos in Trash").font(.title2)
                                    Text("Photos moved to Trash can be put back from here.").foregroundStyle(.secondary)
                                } else {
                                    Text(model.library.activePhotos.isEmpty ? "A new home for your photographs" : "No photographs in this view").font(.title2)
                                    Text("Import into projects. Organise with albums. Keep every original.").foregroundStyle(.secondary)
                                    Button(action: model.importPanel) { Label("Import Photographs…", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if model.viewer, let photo = model.selected, let repo = model.repository {
                            Group {
                                if model.quickPreview, let url = try? repo.availableOriginalURL(photo) {
                                    QuickPreviewPhotoViewer(photo: photo, url: url)
                                } else if model.comparisonID != nil, model.comparisonPhotos.count >= 2 {
                                    PhotoComparisonView(photos: model.comparisonPhotos, repository: repo)
                                } else if let url = try? repo.availableOriginalURL(photo) {
                                    PhotoViewer(photo: photo, url: url, original: model.compareOriginal).id(photo.id)
                                } else {
                                    MissingOriginalView(photo: photo)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .simultaneousGesture(TapGesture().onEnded {
                                if model.tool == .select { focusedPhotographyPanel = .viewer }
                            })
                            if model.photographyLayout.filmstrip {
                                ScrollView(.horizontal) { LazyHStack(spacing: 10) { ForEach(model.photos) { photo in photoCell(photo, compact: true, photographyFocus: .filmstrip) } }.padding(12) }
                                    .scrollIndicators(.hidden).frame(height: 128).workspaceGlass(radius: 18).padding(.horizontal, 16).padding(.bottom, 14)
                                    .focusable().focusEffectDisabled()
                                    .focused($focusedPhotographyPanel, equals: .filmstrip)
                                    .accessibilityLabel("Photography Filmstrip")
                            }
                        } else if model.browserLayout == .list {
                            PhotoListBrowser(model: model, photos: model.photos)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.gridThumbnailSize.columnWidth), spacing: 16)], spacing: 18) {
                                    ForEach(model.photos) { photo in photoCell(photo, compact: false, manualReorder: true) }
                                }.padding(20)
                            }
                        }
                    }.frame(minWidth: 400).background(Color(white: 0.055))
                        .focusable().focusEffectDisabled()
                        .focused($focusedPhotographyPanel, equals: model.viewer ? .viewer : .browser)
                        .simultaneousGesture(TapGesture().onEnded {
                            if !model.viewer { model.activeBrowserPane = .primary }
                        })
                        .keywordShortcuts(for: model)
                        .onKeyPress(.escape) {
                            if model.isPhotographyFullScreen {
                                model.togglePhotographyFullScreen()
                                return .handled
                            }
                            guard model.viewer else { return .ignored }
                            model.exitViewer()
                            return .handled
                        }
                    if model.activeLightTable == nil, model.secondaryBrowser.visible, !model.viewer, !model.places, !model.batchMode, !model.isPeopleGallery {
                        SecondaryBrowserPane(model: model)
                    }
                    if model.activeLightTable == nil, model.photographyLayout.inspector && !model.isViewingTrash && !model.isPeopleGallery {
                        Inspector().frame(minWidth: 260, idealWidth: 290, maxWidth: 340).workspaceGlass(radius: 20).padding(10)
                            .focusable().focusEffectDisabled()
                            .focused($focusedPhotographyPanel, equals: .inspector)
                    }
                }
                Divider()
                if model.peopleScan == nil {
                    HStack(spacing: 8) {
                        if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "checkmark.shield").foregroundStyle(.secondary) }
                        Text(model.status).font(.caption).lineLimit(2)
                        Spacer()
                        if !model.isPeopleGallery {
                            Text("\(model.activeLightTable?.items.count ?? model.photos.count) photos")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 10).background(.ultraThinMaterial)
                }
            }
        }
        .disabled(model.busy || model.repository == nil)
        .searchable(text: model.isPeopleGallery ? $model.peopleGallerySearch : $model.search,
                    prompt: model.isPeopleGallery ? Text("Search people by name") : Text("Search photos and metadata"))
        .toolbar {
            ForEach(model.toolbarConfiguration.items) { item in
                ToolbarItem(id: item.rawValue) {
                    ConfiguredToolbarItemView(item: item).environmentObject(model)
                }
            }
        }
        .background(PhotographyWindowReader { model.attachPhotographyWindow($0) })
    }
    var body: some View {
        VStack(spacing: 0) {
            workspaceView
            if model.importInProgress { ImportProgressBar() }
            if let scan = model.peopleScan, model.peopleSummary == nil {
                PeopleScanProgressView(task: scan.task, progress: scan.progress)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $model.showAutoStack) { AutoStackView().environmentObject(model) }
        .sheet(isPresented: $model.showSlideshow) {
            if let repository = model.repository, !model.slideshowPhotos.isEmpty { SlideshowView(photos: model.slideshowPhotos, repository: repository) }
        }
        .sheet(isPresented: $model.showSmartAlbum) { SmartAlbumView().environmentObject(model) }
        .sheet(isPresented: $model.showAdvancedSearch) { AdvancedSearchView().environmentObject(model) }
        .sheet(item: $model.peopleReview) { review in
            PeopleReviewView(review: review).environmentObject(model)
        }
        .sheet(item: $model.peopleSummary, onDismiss: model.finishPeopleSummary) { request in
            PeopleReviewSummaryView(request: request).environmentObject(model)
        }
        .sheet(item: $model.unnamedFaceReview) { review in
            UnnamedFaceQueueView(review: review).environmentObject(model)
        }
        .sheet(item: $model.personNameEditor) { request in
            PersonNameEditor(request: request).environmentObject(model)
        }
        .sheet(item: $model.personOverview) { request in
            PersonOverviewView(request: request).environmentObject(model)
        }
        .sheet(isPresented: $model.showDeviceImport, onDismiss: model.finishDevicePicker) {
            DeviceImportView(discovery: model.cameraDiscovery).environmentObject(model)
        }
        .sheet(item: $model.tetherCaptureSource) { source in
            TetherCaptureView(source: source).environmentObject(model)
        }
        .sheet(isPresented: $model.showImportOptions, onDismiss: model.finishImportOptions) {
            ImportOptionsView().environmentObject(model)
        }
        .sheet(isPresented: $model.showRelocationOptions, onDismiss: model.chooseRelocationDestination) {
            RelocationOptionsView().environmentObject(model)
        }
        .sheet(isPresented: $model.showKeywordVocabulary) {
            KeywordVocabularyView().environmentObject(model)
        }
        .sheet(isPresented: $model.showKeywordGroupEditor) {
            KeywordGroupEditor().environmentObject(model)
        }
        .sheet(isPresented: $model.showAdjustmentPresetManager) {
            AdjustmentPresetManagerView().environmentObject(model)
        }
        .sheet(isPresented: $model.showToolbarEditor) {
            ToolbarConfigurationView().environmentObject(model)
        }
        .sheet(isPresented: $model.showCommandEditor) {
            KeyboardCommandEditorView().environmentObject(model)
        }
        .sheet(isPresented: $model.showListColumnEditor) {
            ListColumnEditorView().environmentObject(model)
        }
        .sheet(item: $model.adjustmentPresetReview) { review in
            AdjustmentPresetReviewView(review: review).environmentObject(model)
        }
        .sheet(item: $model.batchMetadataReview) { review in
            BatchMetadataView(review: review).environmentObject(model)
        }
        .sheet(item: $model.inheritedIPTCReview) { review in
            InheritedIPTCReviewView(review: review).environmentObject(model)
        }
        .sheet(item: $model.locationEditor) { edit in
            PhotoLocationEditor(edit: edit).environmentObject(model)
        }
        .sheet(item: $model.gpxLocationEditor) { edit in
            GPXLocationView(edit: edit).environmentObject(model)
        }
        .sheet(item: $model.gpxWaypointAssignment) { assignment in
            GPXWaypointAssignmentView(assignment: assignment).environmentObject(model)
        }
        .sheet(item: $model.captureDateCorrection) { correction in
            CaptureDateView(correction: correction).environmentObject(model)
        }
        .sheet(item: $model.externalEditHandoff) { handoff in
            ExternalEditReturnView(handoff: handoff).environmentObject(model)
        }
        .sheet(isPresented: $model.showPrintOptions) { PrintLayoutView().environmentObject(model) }
        .sheet(isPresented: $model.showExportOptions) { ExportOptionsView().environmentObject(model) }
        .sheet(item: $collectionEditor) { CollectionNameSheet($0).environmentObject(model) }
        .alert("Isonique", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert(model.originalJobResult?.title ?? "Original Search",
               isPresented: Binding(get: { model.originalJobResult != nil },
                                    set: { if !$0 { model.originalJobResult = nil } })) {
            Button("OK") { model.originalJobResult = nil }
        } message: {
            Text(model.originalJobResult?.details ?? "")
        }
        .onChange(of: model.scope) { _, _ in
            model.activeBrowserPane = .primary
            if model.scope == "people" || model.scope.hasPrefix("person:") || model.isPeopleGallery { model.places = false }
            if model.isPeopleGallery { model.batchMode = false }
            if model.isViewingTrash {
                model.search = ""; model.ratingFilter = .all; model.originalFilter = .all; model.colorFilter = .all; model.advancedSearch = nil
            }
            if model.selected == nil { model.selection = model.photos.first?.id }
            model.batchSelection = []
            model.showBrowser()
        }
        .modifier(PhotographyWorkspaceInteractionModifier(model: model,
            columnVisibility: $columnVisibility, focusedPanel: $focusedPhotographyPanel))
        .onChange(of: model.compareOriginal) { _, original in if original { model.stopComparison() } }
        .onChange(of: model.activeCurveSampling) { _, active in
            if active == nil, model.curveSampling != nil { model.curveSampling = nil }
        }
        .onChange(of: model.activeWhiteBalanceSampling) { _, active in
            if active == nil, model.whiteBalanceSampling != nil { model.whiteBalanceSampling = nil }
        }
        .onChange(of: model.activeTargetedColorSampling) { _, active in
            if active == nil, model.targetedColorSampling != nil { model.targetedColorSampling = nil }
        }
        .onChange(of: model.search) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.ratingFilter) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.originalFilter) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.advancedSearch) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.colorFilter) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in model.refreshOriginalStatus() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in model.refreshOriginalStatus() }
        .onChange(of: model.selection) { _, _ in model.tool = .select; model.compareOriginal = false }
    }
    @ViewBuilder func photoCell(_ photo: Photo, compact: Bool, onSelect: (() -> Void)? = nil,
                                manualReorder: Bool = false,
                                photographyFocus: PhotographyWorkspaceFocus? = nil) -> some View {
        if let repo = model.repository {
            let url = try? repo.availableOriginalURL(photo)
            let isSelected = model.batchMode ? model.batchSelection.contains(photo.id) : model.selection == photo.id
            let selectedColor = model.quickPreview ? Color.yellow : Color.accentColor
            Button {
                model.activeBrowserPane = .primary
                if let onSelect {
                    onSelect()
                } else if model.batchMode {
                    if !model.batchSelection.insert(photo.id).inserted { model.batchSelection.remove(photo.id) }
                    model.selection = photo.id
                } else { model.selectBrowserPhoto(photo.id); model.viewer = true }
                focusedPhotographyPanel = photographyFocus ?? (model.viewer ? .viewer : .browser)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if let url {
                            Thumbnail(request: .init(photoID: photo.id, url: url, adjustments: photo.adjustments,
                                                     maximum: compact ? 220 : model.gridThumbnailSize.decodeMaximum,
                                                     revision: model.originalStatusRevision),
                                      cache: model.thumbnailCache)
                        }
                        else { Label("Original unavailable", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
                    }.frame(height: compact ? 76 : model.gridThumbnailSize.imageHeight)
                        .frame(maxWidth: .infinity).background(Color.black.opacity(0.3)).clipped()
                    HStack {
                        if model.batchMode { Image(systemName: model.batchSelection.contains(photo.id) ? "checkmark.circle.fill" : "circle") }
                        Text(photo.displayName).lineLimit(1)
                        if photo.id == model.comparisonID { Image(systemName: "pin.fill").accessibilityLabel("Comparison reference") }
                        if let stackID = photo.stackID {
                            StackBadge(stackID: stackID, photo: photo, model: model)
                        }
                        if photo.referencedPath != nil { Image(systemName: "link").accessibilityLabel("Referenced original") }
                        if let label = photo.colorLabel {
                            Image(systemName: "circle.fill").foregroundStyle(label.tint).accessibilityLabel(model.name(for: label))
                        }
                    }.font(.caption)
                    if !compact { HStack { Text(photo.rating == RatingRules.rejected ? "Rejected" : RatingRules.stars(photo.rating)).foregroundStyle(.orange); Spacer(); if photo.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange) } }.font(.caption).frame(height: 14) }
                }.padding(7).frame(width: compact ? 110 : nil)
                    .background(isSelected ? selectedColor.opacity(0.18) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? selectedColor : Color.white.opacity(0.07), lineWidth: isSelected ? 2 : 1))
            }.buttonStyle(.plain)
            .draggable(photo.id.uuidString)
            .dropDestination(for: String.self) { values, _ in
                guard manualReorder, let value = values.first, let id = UUID(uuidString: value),
                      model.canManuallyOrder(model.scope) else { return false }
                let source = model.library.photos.first { $0.id == id }
                let moving = source.map { model.manualMoveIDs(for: $0, scope: model.scope) } ?? [id]
                model.moveManualPhotos(moving, before: model.manualDropTargetID(for: photo, scope: model.scope),
                                       scope: model.scope)
                return true
            }
            .contextMenu {
                PhotoContextActions(model: model, photo: photo, url: url)
                if manualReorder {
                    Divider()
                    Button("Move to Beginning") { model.moveManualPhoto(photo, toEnd: false, scope: model.scope) }
                        .disabled(!model.canManuallyOrder(model.scope))
                    Button("Move to End") { model.moveManualPhoto(photo, toEnd: true, scope: model.scope) }
                        .disabled(!model.canManuallyOrder(model.scope))
                }
            }
        }
    }
}
struct EditBar: View {
    @EnvironmentObject var model: Workspace
    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                controls
                ScrollView(.horizontal) { controls }.scrollIndicators(.hidden)
            }
            if model.tool == .straighten {
                HStack {
                    Text("Straighten").font(.caption)
                    Button { model.nudgeStraighten(-0.1) } label: { Image(systemName: "minus") }
                        .help("Decrease straighten angle by 0.1°").accessibilityLabel("Decrease straighten angle by 0.1 degrees")
                    Slider(value: Binding(get: { model.selected?.adjustments.straighten ?? 0 }, set: { value in
                        model.edit { $0.adjustments.straighten = StraightenRules.clamp(value); $0.adjustments.crop = nil }
                    }), in: StraightenRules.range).frame(maxWidth: 280).accessibilityLabel("Straighten angle")
                    Button { model.nudgeStraighten(0.1) } label: { Image(systemName: "plus") }
                        .help("Increase straighten angle by 0.1°").accessibilityLabel("Increase straighten angle by 0.1 degrees")
                    Text("\(model.selected?.adjustments.straighten ?? 0, specifier: "%.1f")°").monospacedDigit().font(.caption).frame(width: 48)
                    Button("Level") { model.edit { $0.adjustments.straighten = 0; $0.adjustments.crop = nil } }
                    Button("Done") { model.tool = .select }
                    Spacer()
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
    }
    var controls: some View {
        HStack(spacing: 14) {
            Group {
                tool("Select", icon: "cursorarrow", mode: .select)
                Button { model.rotate(-1) } label: { Label("Left", systemImage: "rotate.left") }.help("Rotate 90° left; clears crop")
                Button { model.rotate(1) } label: { Label("Right", systemImage: "rotate.right") }.help("Rotate 90° right; clears crop")
                Menu {
                    ForEach(FlipAxis.allCases) { axis in Button(axis.rawValue) { model.flip(axis) } }
                } label: { Label("Flip", systemImage: "arrow.left.and.right") }
                Divider().frame(height: 20)
                tool("Crop", icon: "crop", mode: .crop)
                tool("Straighten", icon: "level", mode: .straighten)
                Menu {
                    Button("Dodge Brush") { model.chooseBrush(.dodge) }
                    Button("Burn Brush") { model.chooseBrush(.burn) }
                    Button("Saturation Brush") { model.chooseBrush(.saturation) }
                    Button("Definition Brush") { model.chooseBrush(.definition) }
                    Button("Sharpening Brush") { model.chooseBrush(.sharpening) }
                    Button("Luminance Noise Reduction Brush") { model.chooseBrush(.noiseReduction) }
                    Button("Contrast Brush") { model.chooseBrush(.contrast) }
                    Button("Blur Brush") { model.chooseBrush(.blur) }
                    Button("Tint Brush") { model.chooseBrush(.tint) }
                    Button("Skin Smoothing Brush") { model.chooseBrush(.skinSmoothing) }
                    Button("Polarize Brush") { model.chooseBrush(.polarize) }
                    Button("Halo Reduction Brush") { model.chooseBrush(.haloReduction) }
                } label: {
                    Label("Brush", systemImage: "paintbrush.pointed")
                        .foregroundStyle(model.tool == .brush ? Color.accentColor : .primary)
                }.disabled(!model.canBrush)
                Menu {
                    Button("Repair Spot") { model.chooseSpotRemoval(.repair) }
                    Button("Clone Spot") { model.chooseSpotRemoval(.clone) }
                    Button("Manual Red-Eye") { model.chooseRedEyeCorrection() }
                } label: {
                    Label("Retouch", systemImage: "bandage")
                        .foregroundStyle(model.tool == .spot || model.tool == .redEye ? Color.accentColor : .primary)
                }.disabled(!model.canSpotRemove && !model.canCorrectRedEye)
                Divider().frame(height: 20)
                Button(action: model.lift) { Label("Lift", systemImage: "eyedropper") }
                    .disabled(!model.canLift).help("Copy adjustments and metadata from this photo")
                Button(action: model.stamp) { Label("Stamp", systemImage: "eyedropper.full") }.disabled(!model.canStamp).help("Apply the adjustments and metadata selected in Inspector")
                Divider().frame(height: 20)
                Toggle(isOn: $model.compareOriginal) { Label("Original", systemImage: "square.on.square") }.toggleStyle(.button).disabled(model.tool != .select).help("Compare with the untouched original")
            }.disabled(model.selected == nil)
            Button { model.undoEdit() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Undo photo edit").accessibilityLabel("Undo photo edit")
            Button { model.redoEdit() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Redo photo edit").accessibilityLabel("Redo photo edit")
        }.buttonStyle(.borderless).font(.caption).fixedSize(horizontal: true, vertical: false)
    }
    func tool(_ title: String, icon: String, mode: EditTool) -> some View {
        Button { model.chooseTool(mode) } label: { Label(title, systemImage: icon).foregroundStyle(model.tool == mode ? Color.accentColor : .primary) }.help(title)
    }
}
struct PhotoViewer: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    let url: URL
    let original: Bool
    @State private var image: ViewerImage?
    @State private var completedRequest: RenderRequest?
    @State private var loupePoint = CGPoint(x: 0.5, y: 0.5)
    @State private var pendingSample: CurveSampleWork?
    @State private var pendingWhiteBalanceSample: WhiteBalanceSampleWork?
    @State private var pendingTargetedColorSample: TargetedColorSampleWork?
    @State private var geometry: PhotoGeometry?
    @State private var erasingBrush = false
    @State private var showBrushMask = false
    @State private var brushMaskOverlay: BrushMaskOverlayFrame?
    @AppStorage("brush.size") private var brushSize = 12.0
    @AppStorage("brush.softness") private var brushSoftness = 70.0
    @AppStorage("brush.strength") private var brushStrength = 50.0
    @AppStorage("brush.edgeAware") private var edgeAwareBrush = true
    @AppStorage(BrushPressurePreferences.sizeCurveKey)
    private var brushPressureSizeCurve = BrushPressureCurve.linear.rawValue
    @AppStorage(BrushPressurePreferences.strengthCurveKey)
    private var brushPressureStrengthCurve = BrushPressureCurve.linear.rawValue
    @AppStorage(BrushPressurePreferences.minimumSizeKey) private var brushPressureMinimumSize = 20.0
    @AppStorage(BrushPressurePreferences.minimumStrengthKey) private var brushPressureMinimumStrength = 10.0
    @AppStorage("spot.size") private var spotSize = 12.0
    @AppStorage("redEye.size") private var redEyeSize = 8.0
    @AppStorage("redEye.darkness") private var redEyeDarkness = 55.0
    @State private var failure: String?
    @State private var zoomScale: CGFloat?
    @State private var pinchBaseScale: CGFloat?
    @State private var pinchFitScale: CGFloat?
    @State private var pinchActive = false
    @State private var viewerViewportSize = CGSize.zero
    @State private var cropSize = CGSize(width: 1, height: 1)
    @AppStorage("crop.aspect") private var cropAspect = 0.0
    @AppStorage("crop.locked") private var cropLocked = false
    @State private var draft = PhotoCrop(x: 0, y: 0, width: 1, height: 1)
    private struct RenderRequest: Equatable {
        let url: URL
        let originalStatus: Int
        let isCropping: Bool
        let adjustments: Adjustments
        let maximum: CGFloat?
        let profile: Data?
    }
    private struct BrushMaskOverlayRequest: Equatable {
        let url: URL
        let adjustments: Adjustments
        let adjustment: LocalBrushAdjustment
        let instanceID: UUID?
        let maximum: CGFloat?
    }
    private struct BrushMaskOverlayFrame {
        let request: BrushMaskOverlayRequest
        let image: CGImage?
    }

    var body: some View {
        let request = renderRequest
        let maskRequest = brushMaskOverlayRequest
        let maskOverlay = brushMaskOverlay.flatMap { $0.request == maskRequest ? $0.image : nil }
        let sampler = model.activeCurveSampling
        let sampleWork = pendingSample.flatMap { $0.request == sampler ? $0 : nil }
        let whiteBalanceSampler = model.activeWhiteBalanceSampling
        let whiteBalanceSampleWork = pendingWhiteBalanceSample.flatMap { $0.request == whiteBalanceSampler ? $0 : nil }
        let targetedColorSampler = model.activeTargetedColorSampling
        let targetedColorSampleWork = pendingTargetedColorSample.flatMap { $0.request == targetedColorSampler ? $0 : nil }
        VStack(spacing: 10) {
            
            if let image {
                if model.tool == .crop { CropCanvas(image: image, crop: $draft, pixelSize: cropSize, aspect: cropLocked && cropAspect > 0 ? cropAspect : nil).padding(16) }
                else if model.tool == .brush, let geometry, geometry.matches(photo.adjustments) {
                    brushCanvas(image: image, geometry: geometry, overlay: maskOverlay)
                }
                else if model.tool == .spot, let geometry, geometry.matches(photo.adjustments) {
                    SpotRemovalCanvas(image: image, geometry: geometry, photo: photo, radius: spotSize / 200)
                        .padding(16)
                }
                else if model.tool == .redEye, let geometry, geometry.matches(photo.adjustments) {
                    RedEyeCanvas(image: image, geometry: geometry, photo: photo,
                                 radius: redEyeSize / 200, darkness: redEyeDarkness / 100)
                        .padding(16)
                }
                else if zoom && model.tool == .select {
                    ScrollView([.horizontal, .vertical]) {
                        ClippingPreview(image: image)
                            .frame(width: image.size.width * (zoomScale ?? 1),
                                   height: image.size.height * (zoomScale ?? 1))
                            .overlay { if model.loupeActive { loupeTarget } }
                    }
                }
                else {
                    ClippingPreview(image: image).aspectRatio(image.size, contentMode: .fit)
                        .overlay {
                            if model.loupeActive { loupeTarget }
                            if model.tool == .straighten {
                                GeometryReader { geometry in
                                    Path { path in
                                        for n in 1...8 {
                                            let x = geometry.size.width * CGFloat(n) / 9, y = geometry.size.height * CGFloat(n) / 9
                                            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                        }
                                    }.stroke(.yellow.opacity(0.5), lineWidth: 0.5)
                                }.allowsHitTesting(false)
                            }
                        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let failure { ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle", description: Text(failure)) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.overlay(alignment: .top) {
            HStack(spacing: 14) {
                Image(systemName: original ? "photo" : "slider.horizontal.3").foregroundStyle(.secondary)
                Text(photo.displayName).font(.caption.weight(.medium)).lineLimit(1)
                if original { Text("Original").font(.caption).foregroundStyle(.secondary) }
                if model.proofEnabled { Text("RGB Proof").font(.caption).foregroundStyle(.yellow) }
                if image != nil && model.clipping.enabled { ClippingLegend(settings: model.clipping) }
                Divider().frame(height: 16)
                Button(action: model.toggleLoupe) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(model.loupeActive ? Color.accentColor : .primary)
                }.buttonStyle(.plain).help(model.loupeActive ? "Hide Loupe" : "Show Loupe")
                    .accessibilityLabel(model.loupeActive ? "Hide Loupe" : "Show Loupe")
                    .disabled(model.tool != .select)
                Button(zoom ? "Fit" : "100%") { zoomScale = ViewerZoom.toggled(zoomScale) }
                    .buttonStyle(.plain).font(.caption.monospacedDigit()).help("Toggle actual pixels")
                    .disabled(model.tool != .select && model.tool != .brush)
                if let zoomScale {
                    Text(ViewerZoom.percentage(zoomScale)).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).accessibilityLabel("Viewer zoom")
                }
            }.padding(.horizontal, 16).padding(.vertical, 11).workspaceGlass(radius: 24).padding(16)
        }.overlay(alignment: .bottomTrailing) {
            if model.loupeActive {
                if let image, completedRequest == request {
                    VStack(spacing: 0) {
                        LoupePanel(image: image, point: loupePoint)
                        if let sampler {
                            VStack(spacing: 6) {
                                Text("\(sampler.channel.rawValue) curve").font(.caption.weight(.semibold))
                                if sampleWork != nil {
                                    ProgressView("Sampling pixel").controlSize(.small)
                                } else {
                                    Text("Click the image or use the current target.")
                                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                    Button("Add Curve Point") { queueSample(at: loupePoint) }
                                }
                                Button("Cancel Sampling") { model.curveSampling = nil }
                            }.font(.caption).frame(width: 156).padding([.horizontal, .bottom], 10)
                        } else if whiteBalanceSampler != nil {
                            VStack(spacing: 6) {
                                Text("White Balance").font(.caption.weight(.semibold))
                                if whiteBalanceSampleWork != nil {
                                    ProgressView("Sampling pixel").controlSize(.small)
                                } else {
                                    Text("Target an opaque, unclipped neutral grey or white pixel.")
                                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                    Button("Set White Balance") { queueSample(at: loupePoint) }
                                }
                                Button("Cancel Sampling") { model.whiteBalanceSampling = nil }
                            }.font(.caption).frame(width: 156).padding([.horizontal, .bottom], 10)
                        } else if targetedColorSampler != nil {
                            VStack(spacing: 6) {
                                Text("Targeted Color").font(.caption.weight(.semibold))
                                if targetedColorSampleWork != nil {
                                    ProgressView("Sampling color").controlSize(.small)
                                } else {
                                    Text("Target a colored pixel to create a reusable range.")
                                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                    Button("Add Color Range") { queueSample(at: loupePoint) }
                                }
                                Button("Cancel Sampling") { model.targetedColorSampling = nil }
                            }.font(.caption).frame(width: 156).padding([.horizontal, .bottom], 10)
                        }
                    }.workspaceGlass().padding(16)
                } else if failure == nil {
                    ProgressView("Loading Loupe").font(.caption).padding(12).workspaceGlass().padding(16)
                }
            }
        }.safeAreaInset(edge: .bottom) {
            if model.tool == .crop {
                CropOptionsView(crop: $draft, aspect: $cropAspect, locked: $cropLocked, size: cropSize,
                    cancel: { model.tool = .select }, apply: { model.edit { $0.adjustments.crop = draft }; model.tool = .select })
                    .padding(12).workspaceGlass().padding(8)
            } else if model.tool == .brush {
                let instances = photo.adjustments.localBrushInstances(for: model.brushAdjustment)
                let instance = model.brushInstanceID.flatMap { id in instances.first { $0.id == id } }
                    ?? instances.first
                let settings = instance?.maskSettings ?? LocalBrushMaskSettings()
                BrushControls(adjustment: $model.brushAdjustment, instanceID: $model.brushInstanceID,
                              erasing: $erasingBrush,
                              size: $brushSize, softness: $brushSoftness, strength: $brushStrength,
                              edgeAware: $edgeAwareBrush, showMask: $showBrushMask,
                              pressureSizeCurve: $brushPressureSizeCurve,
                              pressureStrengthCurve: $brushPressureStrengthCurve,
                              pressureMinimumSize: $brushPressureMinimumSize,
                              pressureMinimumStrength: $brushPressureMinimumStrength,
                              instances: instances,
                              hasMask: instance?.strokes.contains { !$0.erasing } == true,
                              maskOpacity: settings.opacity, maskInverted: settings.inverted,
                              tintSettings: instance?.tintSettings ?? LocalTintSettings(),
                              skinSmoothingSettings: instance?.skinSmoothingSettings ?? LocalSkinSmoothingSettings(),
                              polarizeSettings: instance?.polarizeSettings ?? LocalPolarizeSettings(),
                              haloReductionSettings: instance?.haloReductionSettings ?? LocalHaloReductionSettings(),
                              setOpacity: { model.setBrushMaskOpacity($0, for: model.brushAdjustment) },
                              setTintSettings: model.setLocalTintSettings,
                              setSkinSmoothingSettings: model.setLocalSkinSmoothingSettings,
                              setPolarizeSettings: model.setLocalPolarizeSettings,
                              setHaloReductionSettings: model.setLocalHaloReductionSettings,
                              createInstance: { model.createBrushInstance(model.brushAdjustment) },
                              renameInstance: model.renameBrushInstance,
                              setInstanceEnabled: model.setBrushInstanceEnabled,
                              duplicateInstance: model.duplicateBrushInstance,
                              moveInstance: model.moveBrushInstance,
                              deleteInstance: model.deleteBrushInstance,
                              invert: { model.invertBrushMask(model.brushAdjustment) },
                              reset: { model.clearBrushMask(model.brushAdjustment) },
                              done: { model.tool = .select })
                    .padding(12).workspaceGlass().padding(8)
            } else if model.tool == .spot {
                SpotRemovalControls(photo: photo, size: $spotSize)
                    .padding(12).workspaceGlass().padding(8)
            } else if model.tool == .redEye {
                RedEyeControls(photo: photo, size: $redEyeSize, darkness: $redEyeDarkness)
                    .padding(12).workspaceGlass().padding(8)
            }
        }.padding(.top, 8)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ViewerViewportSizePreference.self, value: proxy.size)
        })
        .onPreferenceChange(ViewerViewportSizePreference.self) { viewerViewportSize = $0 }
        .simultaneousGesture(viewerMagnificationGesture)
        .onChange(of: model.tool) { _, tool in
            if tool == .crop { draft = photo.adjustments.crop ?? PhotoCrop(x: 0, y: 0, width: 1, height: 1) }
            if tool != .brush { erasingBrush = false; showBrushMask = false }
        }
        .onChange(of: model.brushAdjustment) { _, adjustment in
            erasingBrush = false
            model.selectBrushInstance(for: adjustment)
        }
        .task(id: sampleWork) {
            guard let sampleWork else { return }
            do {
                let input = try await sampleWork.load(from: url)
                guard !Task.isCancelled, model.activeCurveSampling == sampleWork.request else { return }
                pendingSample = nil
                model.finishCurveSampling(sampleWork.request, input: input)
            } catch {
                guard !Task.isCancelled, model.activeCurveSampling == sampleWork.request else { return }
                pendingSample = nil
                model.curveSampling = nil
                model.error = error.localizedDescription
            }
        }
        .task(id: whiteBalanceSampleWork) {
            guard let whiteBalanceSampleWork else { return }
            do {
                let sample = try await whiteBalanceSampleWork.load(from: url)
                guard !Task.isCancelled, model.activeWhiteBalanceSampling == whiteBalanceSampleWork.request else { return }
                pendingWhiteBalanceSample = nil
                model.finishWhiteBalanceSampling(whiteBalanceSampleWork.request, sample: sample)
            } catch {
                guard !Task.isCancelled, model.activeWhiteBalanceSampling == whiteBalanceSampleWork.request else { return }
                pendingWhiteBalanceSample = nil
                model.whiteBalanceSampling = nil
                model.error = error.localizedDescription
            }
        }
        .task(id: targetedColorSampleWork) {
            guard let targetedColorSampleWork else { return }
            do {
                let sample = try await targetedColorSampleWork.load(from: url)
                guard !Task.isCancelled, model.activeTargetedColorSampling == targetedColorSampleWork.request else { return }
                pendingTargetedColorSample = nil
                model.finishTargetedColorSampling(targetedColorSampleWork.request, sample: sample)
            } catch {
                guard !Task.isCancelled, model.activeTargetedColorSampling == targetedColorSampleWork.request else { return }
                pendingTargetedColorSample = nil
                model.targetedColorSampling = nil
                model.error = error.localizedDescription
            }
        }
        .task(id: maskRequest) {
            guard let maskRequest else {
                brushMaskOverlay = nil
                return
            }
            do {
                let overlay = try await Task.detached(priority: .userInitiated) {
                    try Renderer.localBrushMaskOverlay(maskRequest.url,
                        adjustments: maskRequest.adjustments, adjustment: maskRequest.adjustment,
                        instanceID: maskRequest.instanceID,
                        maxDimension: maskRequest.maximum)
                }.value
                guard !Task.isCancelled, brushMaskOverlayRequest == maskRequest else { return }
                brushMaskOverlay = BrushMaskOverlayFrame(request: maskRequest, image: overlay)
            } catch {
                guard !Task.isCancelled, brushMaskOverlayRequest == maskRequest else { return }
                brushMaskOverlay = nil
                model.error = "Could not show the brush mask. " + error.localizedDescription
            }
        }
        .task(id: request) {
            if request.isCropping, let size = try? Renderer.dimensions(url, adjustments: request.adjustments) { cropSize = size }
            do {
                let frame = try await model.viewerRenderCache.frame(url: request.url, adjustments: request.adjustments,
                                                                   maximum: request.maximum, revision: request.originalStatus)
                let preview = try await ViewerImage.prepare(frame.image, proofProfile: request.profile)
                guard !Task.isCancelled else { return }
                image = preview
                geometry = frame.geometry
                completedRequest = request
                failure = nil
            } catch {
                guard !Task.isCancelled else { return }
                image = nil
                geometry = nil
                completedRequest = nil
                failure = error.localizedDescription
            }
        }
    }

    private var loupeTarget: some View {
        LoupeTarget(point: $loupePoint,
                    sample: model.activeCurveSampling == nil && model.activeWhiteBalanceSampling == nil &&
                        model.activeTargetedColorSampling == nil ? nil : queueSample)
    }

    private var zoom: Bool { zoomScale != nil }

    private var viewerMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                guard model.tool == .select || model.tool == .brush else { return }
                if !pinchActive {
                    pinchFitScale = image.map {
                        ViewerZoom.fittedScale(viewportSize: viewerViewportSize, imageSize: $0.size)
                    }
                    pinchBaseScale = zoomScale ?? pinchFitScale
                    pinchActive = true
                }
                zoomScale = ViewerZoom.magnified(from: pinchBaseScale, by: magnification,
                                                  fitScale: pinchFitScale)
            }
            .onEnded { magnification in
                guard pinchActive else { return }
                zoomScale = ViewerZoom.magnified(from: pinchBaseScale, by: magnification,
                                                  fitScale: pinchFitScale)
                pinchBaseScale = nil
                pinchFitScale = nil
                pinchActive = false
            }
    }

    @ViewBuilder
    private func brushCanvas(image: ViewerImage, geometry: PhotoGeometry, overlay: CGImage?) -> some View {
        let pressureMapping = BrushPressureMapping(
            sizeCurve: BrushPressureCurve(rawValue: brushPressureSizeCurve) ?? .linear,
            strengthCurve: BrushPressureCurve(rawValue: brushPressureStrengthCurve) ?? .linear,
            minimumSize: brushPressureMinimumSize / 100,
            minimumStrength: brushPressureMinimumStrength / 100)
        let canvas = BrushCanvas(image: image, geometry: geometry, adjustment: model.brushAdjustment,
                                 erasing: erasingBrush, radius: brushSize / 200,
                                 softness: brushSoftness / 100, strength: brushStrength / 100,
                                 edgeAware: edgeAwareBrush, pressureMapping: pressureMapping,
                                 overlay: overlay, showMask: showBrushMask) {
            model.applyBrushStroke($0, to: photo.id)
        }
        if zoom {
            ScrollView([.horizontal, .vertical]) {
                canvas.frame(width: image.size.width * (zoomScale ?? 1),
                             height: image.size.height * (zoomScale ?? 1))
            }.padding(16)
        } else {
            canvas.padding(16)
        }
    }

    private func queueSample(at point: CGPoint) {
        guard completedRequest == renderRequest, let image else { return }
        let width = image.rendered.width, height = image.rendered.height
        let pixel = LoupeSample(point: point, width: width, height: height, span: 1)
        let center = CGPoint(x: (Double(pixel.x) + 0.5) / Double(width),
                             y: (Double(pixel.y) + 0.5) / Double(height))
        if let request = model.activeCurveSampling, request.photoID == photo.id,
           pendingSample?.request != request {
            pendingSample = CurveSampleWork(request: request, point: center)
        } else if let request = model.activeWhiteBalanceSampling, request.photoID == photo.id,
                  pendingWhiteBalanceSample?.request != request {
            pendingWhiteBalanceSample = WhiteBalanceSampleWork(request: request, point: center)
        } else if let request = model.activeTargetedColorSampling, request.photoID == photo.id,
                  pendingTargetedColorSample?.request != request {
            pendingTargetedColorSample = TargetedColorSampleWork(request: request, point: center)
        }
    }

    private var renderRequest: RenderRequest {
        var settings = original ? Adjustments() : photo.adjustments
        if model.tool == .crop { settings.crop = nil }
        return RenderRequest(url: url, originalStatus: model.originalStatusRevision, isCropping: model.tool == .crop,
                             adjustments: settings,
                             maximum: (model.tool == .spot || model.tool == .redEye ||
                                 (model.tool == .brush && zoom) ||
                                 (model.tool == .select && (zoom || model.loupeActive))) ? nil : 2400,
                             profile: model.proofEnabled ? model.proofProfile : nil)
    }

    private var brushMaskOverlayRequest: BrushMaskOverlayRequest? {
        guard model.tool == .brush, showBrushMask, !original,
              let instance = photo.adjustments.localBrushInstance(id: model.brushInstanceID),
              instance.enabled,
              instance.strokes.contains(where: { !$0.erasing && $0.isValid }) else { return nil }
        return BrushMaskOverlayRequest(url: url, adjustments: photo.adjustments,
            adjustment: model.brushAdjustment, instanceID: instance.id, maximum: zoom ? nil : 2400)
    }
}
struct Inspector: View {
    @EnvironmentObject var model: Workspace
    @State private var tab = "Adjustments"
    @State private var levelsExpanded = false
    @State private var channelLevelsExpanded = false
    @State private var masterCurveExpanded = false
    @State private var channelCurvesExpanded = false
    @State private var adjustmentInputs: (AdjustmentHistogramRequest, AdjustmentHistograms)?
    @State private var inputHistogramError = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Inspector", systemImage: "slider.horizontal.3").font(.headline)
                if model.batchMode { Text("This inspector edits one photo. Use the selection bar above for batch actions.").font(.caption).foregroundStyle(.secondary) }
                if let photo = model.selected {
                    Text(photo.displayName).font(.headline).textSelection(.enabled)
                    Picker("Inspector section", selection: $tab) {
                        Text("Info").tag("Info")
                        Text("Adjustments").tag("Adjustments")
                        Text("Library").tag("Library")
                    }.pickerStyle(.segmented).labelsHidden()
                    if tab == "Info" { PhotoMetadataInspector(photo: photo) }
                    if tab == "Adjustments", model.quickPreview {
                        ContentUnavailableView("Adjustments Paused", systemImage: "bolt.fill",
                            description: Text("Turn off Quick Preview to edit this photograph. Ratings, flags, labels and metadata remain available."))
                    } else if tab == "Adjustments" {
                        VersionFamilyView(photo: photo).id(photo.id)
                        adjustments(photo)
                        VersionsView(photo: photo)
                    }
                    if tab == "Library" { organisation() }
                } else {
                    Text("Select a photograph to view metadata and adjustments.").foregroundStyle(.secondary)
                    Divider()
                    Text("Isonique preserves your originals. Camera RAW support depends on macOS decoders; editing uses Isonique’s own pixel formulas.").font(.caption).foregroundStyle(.secondary)
                    Button("Import XML / XMP Metadata…", action: model.importMetadataPanel).disabled(model.busy || model.library.activePhotos.isEmpty)
                Button("Import & History Options…", action: model.showImportSettings)
                Button("Recover Aperture Originals…", action: model.recoverPanel)
                    Text("Recovery copies and verifies the source first. Legacy albums, referenced files and editing recipes are not migrated.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18)
        }.scrollIndicators(.hidden)
    }
    func adjustments(_ photo: Photo) -> some View {
        let showsInputs = levelsExpanded || channelLevelsExpanded || masterCurveExpanded || channelCurvesExpanded
        let url = showsInputs ? try? model.repository?.originalURL(photo) : nil
        let request = url.map { AdjustmentHistogramRequest(photo: photo, url: $0, originalRevision: model.originalStatusRevision) }
        let inputs = adjustmentInputs.flatMap { $0.0 == request ? $0.1 : nil }
        return VStack(alignment: .leading, spacing: 14) {
            Menu {
                ForEach(AdjustmentPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        model.compareOriginal = false
                        model.edit { $0.adjustments = preset.applying(to: $0.adjustments) }
                    }
                }
                if !model.adjustmentPresets.isEmpty {
                    Divider()
                    ForEach(model.adjustmentPresets) { preset in
                        Button(preset.name) { model.previewAdjustmentPreset(preset) }
                    }
                }
                Divider()
                Button("Manage Custom Presets…") { model.showAdjustmentPresetManager = true }
            } label: { Label("Apply Preset", systemImage: "slider.horizontal.3") }
            Text("Built-in presets replace colour and tone settings. Custom presets preview selected groups before applying.").font(.caption2).foregroundStyle(.secondary)
            adjustment("Exposure", path: \.adjustments.exposure, range: -4...4)
            adjustment("Brightness", path: \.adjustments.brightness, range: -1...1)
            adjustment("Contrast", path: \.adjustments.contrast, range: 0.5...1.5, neutral: 1)
            adjustment("Saturation", path: \.adjustments.saturation, range: 0...2, neutral: 1)
            adjustment("Vibrancy", path: \.adjustments.vibrancy, range: -1...1)
            adjustment("Sepia", path: \.adjustments.sepia, range: 0...1)
            Divider()
            Text("WHITE BALANCE").font(.caption).foregroundStyle(.secondary)
            temperatureAdjustment()
            adjustment("Tint", path: \.adjustments.tint, range: -1...1)
            HStack {
                Button {
                    model.startWhiteBalanceSampling(photoID: photo.id)
                } label: {
                    Label("Sample Neutral", systemImage: "eyedropper")
                }.disabled(model.busy || !model.canShowLoupe)
                Button("Reset") {
                    model.compareOriginal = false
                    model.edit {
                        $0.adjustments.warmth = 0
                        $0.adjustments.temperatureKelvin = WhiteBalanceRules.neutralKelvin
                        $0.adjustments.tint = 0
                    }
                }.disabled(photo.adjustments.warmth == 0 &&
                    photo.adjustments.temperatureKelvin == WhiteBalanceRules.neutralKelvin && photo.adjustments.tint == 0)
            }
            Text("Sample an opaque, unclipped neutral grey or white pixel with the full-resolution Viewer Loupe.")
                .font(.caption2).foregroundStyle(.secondary)
            TargetedColorEditor(photo: photo)
            DisclosureGroup("Black & White") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Black & White", isOn: Binding(get: {
                        model.selected?.adjustments.blackAndWhiteEnabled ?? false
                    }, set: { enabled in
                        model.compareOriginal = false
                        model.edit { $0.adjustments.blackAndWhiteEnabled = enabled }
                    }))
                    VStack(spacing: 10) {
                        adjustment("Red contribution", path: \.adjustments.blackAndWhiteRed,
                                   range: BlackAndWhiteRules.contributionRange, neutral: BlackAndWhiteRules.neutralRed)
                        adjustment("Green contribution", path: \.adjustments.blackAndWhiteGreen,
                                   range: BlackAndWhiteRules.contributionRange, neutral: BlackAndWhiteRules.neutralGreen)
                        adjustment("Blue contribution", path: \.adjustments.blackAndWhiteBlue,
                                   range: BlackAndWhiteRules.contributionRange, neutral: BlackAndWhiteRules.neutralBlue)
                        adjustment("Tint hue", path: \.adjustments.monochromeTintHue,
                                   range: 0...360, neutral: BlackAndWhiteRules.neutralTintHue)
                        adjustment("Tint strength", path: \.adjustments.monochromeTintStrength, range: 0...1)
                    }.disabled(!photo.adjustments.blackAndWhiteEnabled)
                    Button("Reset Black & White") {
                        model.compareOriginal = false
                        model.edit {
                            $0.adjustments.blackAndWhiteEnabled = false
                            $0.adjustments.blackAndWhiteRed = BlackAndWhiteRules.neutralRed
                            $0.adjustments.blackAndWhiteGreen = BlackAndWhiteRules.neutralGreen
                            $0.adjustments.blackAndWhiteBlue = BlackAndWhiteRules.neutralBlue
                            $0.adjustments.monochromeTintHue = BlackAndWhiteRules.neutralTintHue
                            $0.adjustments.monochromeTintStrength = 0
                        }
                    }.disabled(!photo.adjustments.hasBlackAndWhiteRecipe)
                    Text("Neutral contributions use Rec. 709 luminance. Tint strength zero produces pure grayscale.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            Divider()
            HistogramView(photo: photo)
            if showsInputs && inputHistogramError && inputs == nil {
                Text("Adjustment input histograms unavailable").font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("Levels", isExpanded: $levelsExpanded) {
                VStack(spacing: 10) {
                    AdjustmentHistogramView(series: inputs.map { [($0.combinedLevels.luminance, .white)] } ?? [])
                        .frame(height: 48).background(.black.opacity(0.25))
                        .accessibilityHidden(false).accessibilityLabel("Combined Levels input histogram")
                    adjustment("Black point", path: \.adjustments.blackPoint, range: 0...max(0, photo.adjustments.whitePoint - 0.01))
                    adjustment("White point", path: \.adjustments.whitePoint, range: min(1, photo.adjustments.blackPoint + 0.01)...1, neutral: 1)
                    adjustment("Gamma", path: \.adjustments.gamma, range: 0.1...4, neutral: 1)
                    adjustment("Dark quarter", path: \.adjustments.darkLevelQuarter, range: 0...0.5, neutral: 0.25)
                    adjustment("Light quarter", path: \.adjustments.lightLevelQuarter, range: 0.5...1, neutral: 0.75)
                    HStack {
                        AutoLevelsButton(mode: .combined, input: inputs?.combinedLevels, photo: photo)
                        Button("Reset Levels") {
                            model.edit {
                                $0.adjustments.blackPoint = 0
                                $0.adjustments.whitePoint = 1
                                $0.adjustments.gamma = 1
                                $0.adjustments.darkLevelQuarter = 0.25
                                $0.adjustments.lightLevelQuarter = 0.75
                            }
                        }
                    }
                }.padding(.top, 10)
            }
            DisclosureGroup("Channel Levels", isExpanded: $channelLevelsExpanded) {
                ChannelLevelsEditor(photo: photo, input: inputs?.channelLevels).id(photo.id).padding(.top, 10)
            }
            DisclosureGroup("Master Tone Curve", isExpanded: $masterCurveExpanded) {
                VStack(spacing: 10) {
                    ToneCurveGraph(adjustments: photo.adjustments, input: inputs?.masterCurve)
                    adjustment("Shadow output", path: \.adjustments.curveShadows, range: 0...1, neutral: 0.25)
                    adjustment("Midtone output", path: \.adjustments.curveMidtones, range: 0...1, neutral: 0.5)
                    adjustment("Highlight output", path: \.adjustments.curveHighlights, range: 0...1, neutral: 0.75)
                    Button("Reset Curve") { model.edit { $0.adjustments.curveShadows = 0.25; $0.adjustments.curveMidtones = 0.5; $0.adjustments.curveHighlights = 0.75 } }
                }.padding(.top, 10)
            }
            DisclosureGroup("Channel Curves", isExpanded: $channelCurvesExpanded) {
                ChannelCurveEditor(photo: photo, input: inputs?.channelCurves).id(photo.id).padding(.top, 10)
            }
            Text("HIGHLIGHTS & SHADOWS").font(.caption).foregroundStyle(.secondary)
            adjustment("Shadows", path: \.adjustments.shadows, range: 0...1)
            adjustment("Highlights", path: \.adjustments.highlights, range: -1...0)
            DisclosureGroup("Detail") {
                VStack(alignment: .leading, spacing: 10) {
                    adjustment("Sharpening", path: \.adjustments.sharpening, range: 0...1)
                    adjustment("Edge sharpening", path: \.adjustments.edgeSharpening, range: 0...1)
                    adjustment("Luminance noise reduction", path: \.adjustments.luminanceNoiseReduction, range: 0...1)
                    adjustment("Definition", path: \.adjustments.definition,
                               range: DefinitionRules.strengthRange)
                    adjustment("Definition radius (%)", path: \.adjustments.definitionRadius,
                               range: DefinitionRules.radiusRange, neutral: DefinitionRules.neutralRadius)
                    Button("Reset Detail") {
                        model.edit {
                            $0.adjustments.sharpening = 0
                            $0.adjustments.edgeSharpening = 0
                            $0.adjustments.luminanceNoiseReduction = 0
                            $0.adjustments.definition = 0
                            $0.adjustments.definitionRadius = DefinitionRules.neutralRadius
                        }
                    }.disabled(!photo.adjustments.hasDetailAdjustments)
                    Text("Noise reduction smooths luminance. Definition adds bounded local contrast at the selected percentage radius. Sharpening restores fine detail after Repair and Clone without shifting colour.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            DisclosureGroup("Local Brush Masks") {
                VStack(alignment: .leading, spacing: 8) {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Button("Dodge Brush") { model.chooseBrush(.dodge) }
                            Button("Burn Brush") { model.chooseBrush(.burn) }
                        }
                        GridRow {
                            Button("Saturation Brush") { model.chooseBrush(.saturation) }
                            Button("Definition Brush") { model.chooseBrush(.definition) }
                        }
                        GridRow {
                            Button("Sharpening Brush") { model.chooseBrush(.sharpening) }
                            Button("Noise Reduction Brush") { model.chooseBrush(.noiseReduction) }
                        }
                        GridRow {
                            Button("Contrast Brush") { model.chooseBrush(.contrast) }
                            Button("Blur Brush") { model.chooseBrush(.blur) }
                        }
                        GridRow {
                            Button("Tint Brush") { model.chooseBrush(.tint) }
                            Button("Skin Smoothing Brush") { model.chooseBrush(.skinSmoothing) }
                        }
                        GridRow {
                            Button("Polarize Brush") { model.chooseBrush(.polarize) }
                            Button("Halo Reduction Brush") { model.chooseBrush(.haloReduction) }
                        }
                    }.disabled(!model.canBrush)
                    Text("Paint in the Viewer. Each stroke is one undo step.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            DisclosureGroup("Spot Removal") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Repair Spot") { model.chooseSpotRemoval(.repair) }
                        Button("Clone Spot") { model.chooseSpotRemoval(.clone) }
                    }.disabled(!model.canSpotRemove)
                    LabeledContent("Editable spots", value: "\(photo.adjustments.spotRemovals.count)")
                    Button("Reset All Spots", action: model.clearSpots)
                        .disabled(photo.adjustments.spotRemovals.isEmpty)
                    Text("Repair blends source texture into the destination; Clone copies it directly. Source and destination stay editable in the Viewer.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            DisclosureGroup("Red-Eye Correction") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Manual Red-Eye") { model.chooseRedEyeCorrection() }
                        .disabled(!model.canCorrectRedEye)
                    LabeledContent("Editable eyes", value: "\(photo.adjustments.redEyeCorrections.count)")
                    Button("Reset All Red-Eye Corrections", action: model.clearRedEyes)
                        .disabled(photo.adjustments.redEyeCorrections.isEmpty)
                    Text("Click each red pupil in the Viewer, then adjust its size and darkness. Non-red pixels are preserved.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            DisclosureGroup("Color Proofing & Lens") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Choose RGB ICC Profile…", action: model.chooseProofProfile)
                    Toggle("Proof preview", isOn: $model.proofEnabled).disabled(model.proofProfile == nil)
                    Text(model.proofName.isEmpty ? String(localized: "Choose a profile to simulate RGB output color.") : model.proofName).font(.caption2)
                    Text("Proofing affects the viewer only. RGB profiles only; no paper/ink simulation.").font(.caption2).foregroundStyle(.secondary)
                    adjustment("Lens distortion", path: \.adjustments.lensDistortion, range: -1...1)
                    Text("Manual barrel/pincushion correction applies to preview and export; no automatic lens profiles. Edge pixels are extended.").font(.caption2).foregroundStyle(.secondary)
                    Divider()
                    Text("CHROMATIC ABERRATION").font(.caption).foregroundStyle(.secondary)
                    adjustment("Red / Cyan", path: \.adjustments.chromaticAberrationRedCyan, range: -1...1)
                    adjustment("Blue / Yellow", path: \.adjustments.chromaticAberrationBlueYellow, range: -1...1)
                    adjustment("Vignette", path: \.adjustments.vignette, range: 0...1)
                    adjustment("Devignette", path: \.adjustments.devignette, range: 0...1)
                    Button("Reset Lens Effects") {
                        model.edit {
                            $0.adjustments.chromaticAberrationRedCyan = 0
                            $0.adjustments.chromaticAberrationBlueYellow = 0
                            $0.adjustments.vignette = 0
                            $0.adjustments.devignette = 0
                        }
                    }.disabled(!photo.adjustments.hasLensEffects)
                    Text("Aberration and devignetting use the source frame. Vignette follows the final crop and rotation.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            DisclosureGroup("Crop & Rotation") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Button("Rotate Left") { model.rotate(-1) }; Button("Rotate Right") { model.rotate(1) } }
                    Toggle("Flip horizontally", isOn: Binding(get: { photo.adjustments.flipHorizontal }, set: { _ in model.flip(.horizontal) }))
                    Toggle("Flip vertically", isOn: Binding(get: { photo.adjustments.flipVertical }, set: { _ in model.flip(.vertical) }))
                    Button(photo.adjustments.crop == nil ? "Crop…" : "Edit Crop…") { model.chooseTool(.crop) }
                    Button("Remove Crop") { model.tool = .select; model.edit { $0.adjustments.crop = nil } }.disabled(photo.adjustments.crop == nil)
                    adjustment("Straighten", path: \.adjustments.straighten, range: StraightenRules.range, clearsCrop: true)
                    Text("Rotation and straightening clear an existing crop.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            DisclosureGroup("Lift & Stamp Options") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AdjustmentGroup.allCases) { group in
                        Toggle(LocalizedStringKey(group.rawValue), isOn: Binding(get: { model.stampGroups.contains(group) }, set: { included in
                            if included { model.stampGroups.insert(group) } else { model.stampGroups.remove(group) }
                        }))
                    }
                    Divider()
                    Text("Metadata (replaces selected fields)").font(.caption)
                    ForEach(StampMetadata.allCases) { field in
                        Toggle(isOn: Binding(get: { model.stampMetadata.contains(field) }, set: { included in
                            if included { model.stampMetadata.insert(field) } else { model.stampMetadata.remove(field) }
                        })) {
                            HStack {
                                Text(LocalizedStringKey(field.rawValue))
                                if let iptcField = field.iptcField, let source = model.liftedAdjustments?.source {
                                    Spacer()
                                    if let values = source.iptc?[iptcField] {
                                        Text(values.isEmpty ? String(localized: "Empty") : values.joined(separator: " · "))
                                            .lineLimit(1).foregroundStyle(.secondary)
                                    } else if model.liftLookupID == nil {
                                        Text("Unavailable").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    HStack {
                        Button("Lift", action: model.lift).disabled(!model.canLift)
                        Button("Stamp", action: model.stamp).disabled(!model.canStamp)
                    }
                    if let source = model.liftedAdjustments?.source {
                        LabeledContent("Lifted from", value: source.displayName).font(.caption)
                    }
                    if model.liftLookupID != nil {
                        ProgressView("Reading inherited IPTC…").controlSize(.small)
                    }
                    Text("Stamp applies checked settings. Empty IPTC values clear a field. Unavailable IPTC fields are skipped.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            Toggle("Show original", isOn: $model.compareOriginal).disabled(model.tool != .select)
            Button("Reset All Adjustments") { model.tool = .select; model.compareOriginal = false; model.edit { $0.adjustments = Adjustments() } }
            Text("Edits are saved separately. Originals are never rewritten.").font(.caption2).foregroundStyle(.secondary)
            Button("Export Photo…", action: model.exportPanel)
        }.task(id: request) {
            guard !Task.isCancelled else { return }
            inputHistogramError = false
            adjustmentInputs = nil
            guard let request else { return }
            do {
                let histograms = try await request.load()
                guard !Task.isCancelled else { return }
                adjustmentInputs = (request, histograms)
            } catch {
                if !Task.isCancelled { inputHistogramError = true }
            }
        }
    }
    func organisation() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROJECT").font(.caption).foregroundStyle(.secondary)
            Picker("Project", selection: model.binding(\.projectID, fallback: nil)) { Text("Unassigned").tag(nil as UUID?); ForEach(model.library.projects) { Text($0.name).tag(Optional($0.id)) } }
            Text("ALBUMS").font(.caption).foregroundStyle(.secondary)
            if model.library.albums.isEmpty { Text("Create an album using Create in the sidebar.").font(.caption).foregroundStyle(.secondary) }
            ForEach(model.library.albums.filter { $0.rule == nil }) { album in
                Toggle(album.name, isOn: Binding(get: { model.selected?.albumIDs.contains(album.id) ?? false }, set: { included in model.edit { if included { $0.albumIDs.insert(album.id) } else { $0.albumIDs.remove(album.id) } } }))
            }
        }
    }
    func adjustment(_ title: String, path: WritableKeyPath<Photo, Double>, range: ClosedRange<Double>, neutral: Double = 0, clearsCrop: Bool = false) -> some View {
        let value = Binding<Double>(get: { model.selected?[keyPath: path] ?? neutral }, set: { input in
            guard input.isFinite else { return }
            model.compareOriginal = false
            model.edit { photo in
                photo[keyPath: path] = min(range.upperBound, max(range.lowerBound, input))
                if clearsCrop { photo.adjustments.crop = nil }
            }
        })
        return VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: value, format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.trailing)
                Button { value.wrappedValue = neutral } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.borderless).help("Reset \(title)").accessibilityLabel("Reset \(title)")
            }.font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }

    func temperatureAdjustment() -> some View {
        let value = Binding<Double>(get: {
            model.selected?.adjustments.displayedTemperatureKelvin ?? WhiteBalanceRules.neutralKelvin
        }, set: { input in
            guard input.isFinite else { return }
            model.compareOriginal = false
            model.edit {
                $0.adjustments.warmth = 0
                $0.adjustments.temperatureKelvin = WhiteBalanceRules.clamp(kelvin: input)
            }
        })
        return VStack(spacing: 6) {
            HStack {
                Text("Temperature")
                Spacer()
                TextField("Temperature", value: value, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).frame(width: 72).multilineTextAlignment(.trailing)
                Text("K").foregroundStyle(.secondary)
                Button {
                    value.wrappedValue = WhiteBalanceRules.neutralKelvin
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }.buttonStyle(.borderless).help("Reset Temperature").accessibilityLabel("Reset Temperature")
            }.font(.caption)
            Slider(value: value, in: WhiteBalanceRules.minimumKelvin...WhiteBalanceRules.maximumKelvin)
                .accessibilityLabel("Temperature in Kelvin")
        }
    }
}
