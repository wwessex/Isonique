import AppKit
import SwiftUI
import IsoniqueCore
import UniformTypeIdentifiers

enum KeyboardCommandContext: String, Codable, CaseIterable, Hashable {
    case browser = "Browser"
    case viewer = "Viewer"
    case compare = "Compare"
}

enum KeyboardCommandModifier: String, Codable, CaseIterable, Hashable {
    case command
    case option
    case control
    case shift

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }
}

struct KeyboardCommandShortcut: Codable, Equatable, Hashable {
    var key: String
    var modifiers: Set<KeyboardCommandModifier>

    init(_ key: String, modifiers: Set<KeyboardCommandModifier> = []) {
        self.key = Self.normalizedKey(key)
        self.modifiers = modifiers
    }

    var isValid: Bool { Self.availableKeys.contains(key) }

    var displayName: String {
        let ordered: [KeyboardCommandModifier] = [.control, .option, .shift, .command]
        let prefix = ordered.filter(modifiers.contains).map(\.symbol).joined()
        return prefix + Self.keyTitle(key)
    }

    static let availableKeys = Array("abcdefghijklmnopqrstuvwxyz").map(String.init) +
        Array("0123456789").map(String.init) +
        ["=", "-", "/", "\\", "`", "left", "right", "up", "down", "return", "delete"]

    static func keyTitle(_ key: String) -> String {
        switch key {
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return": return "Return"
        case "delete": return "Delete"
        default: return key.uppercased()
        }
    }

    static func normalizedKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "←", "left arrow": return "left"
        case "→", "right arrow": return "right"
        case "↑", "up arrow": return "up"
        case "↓", "down arrow": return "down"
        case "↩", "enter": return "return"
        case "⌫", "backspace": return "delete"
        default: return trimmed
        }
    }

    init?(event: NSEvent) {
        let key: String
        switch event.keyCode {
        case 36, 76: key = "return"
        case 51, 117: key = "delete"
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
            key = String(character)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<KeyboardCommandModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(key, modifiers: modifiers)
        guard isValid else { return nil }
    }
}

enum IsoniqueKeyboardCommand: String, Codable, CaseIterable, Identifiable {
    case toggleBrowser
    case toggleFilmstrip
    case toggleInspector
    case toggleToolbar
    case cyclePanels
    case gridBrowser
    case listBrowser
    case places
    case quickPreview
    case advancedSearch
    case startCompare
    case endCompare
    case promoteCompare
    case removeCompare
    case clippingWarnings
    case loupe
    case lift
    case stamp
    case newVersion
    case duplicateVersion
    case batchChange
    case rating0
    case rating1
    case rating2
    case rating3
    case rating4
    case rating5
    case reject
    case raiseRating
    case lowerRating
    case flag
    case previousPhoto
    case nextPhoto

    var id: String { rawValue }
}

struct KeyboardCommandDefinition: Identifiable, Equatable {
    let command: IsoniqueKeyboardCommand
    let title: String
    let contexts: Set<KeyboardCommandContext>
    let defaultShortcut: KeyboardCommandShortcut

    var id: IsoniqueKeyboardCommand { command }
    var localizedTitle: String { Bundle.main.localizedString(forKey: title, value: nil, table: nil) }
    var contextLabel: String { contexts.map(\.rawValue).sorted().joined(separator: ", ") }

    static let allContexts = Set(KeyboardCommandContext.allCases)
    static let definitions: [Self] = [
        .init(command: .toggleBrowser, title: "Toggle Browser", contexts: allContexts,
              defaultShortcut: .init("b", modifiers: [.command, .option])),
        .init(command: .toggleFilmstrip, title: "Toggle Filmstrip", contexts: allContexts,
              defaultShortcut: .init("f", modifiers: [.command, .option])),
        .init(command: .toggleInspector, title: "Toggle Inspector", contexts: allContexts,
              defaultShortcut: .init("i", modifiers: [.command, .option])),
        .init(command: .toggleToolbar, title: "Toggle Toolbar", contexts: allContexts,
              defaultShortcut: .init("t", modifiers: [.command, .option])),
        .init(command: .cyclePanels, title: "Cycle Photography Panels", contexts: allContexts,
              defaultShortcut: .init("w", modifiers: [.control])),
        .init(command: .gridBrowser, title: "Grid Browser", contexts: allContexts,
              defaultShortcut: .init("g", modifiers: [.control])),
        .init(command: .listBrowser, title: "List Browser", contexts: allContexts,
              defaultShortcut: .init("l", modifiers: [.control])),
        .init(command: .places, title: "Places", contexts: allContexts,
              defaultShortcut: .init("m", modifiers: [.control])),
        .init(command: .quickPreview, title: "Quick Preview", contexts: [.browser, .viewer],
              defaultShortcut: .init("p")),
        .init(command: .advancedSearch, title: "Advanced Search", contexts: allContexts,
              defaultShortcut: .init("f", modifiers: [.command, .shift])),
        .init(command: .startCompare, title: "Compare Photos", contexts: [.browser, .viewer],
              defaultShortcut: .init("o", modifiers: [.option])),
        .init(command: .endCompare, title: "End Comparison", contexts: [.compare],
              defaultShortcut: .init("return", modifiers: [.command])),
        .init(command: .promoteCompare, title: "Promote Compare Select", contexts: [.compare],
              defaultShortcut: .init("p", modifiers: [.option])),
        .init(command: .removeCompare, title: "Remove Compare Select", contexts: [.compare],
              defaultShortcut: .init("delete", modifiers: [.option])),
        .init(command: .clippingWarnings, title: "Highlight Hot & Cold Areas", contexts: [.viewer, .compare],
              defaultShortcut: .init("h", modifiers: [.option, .shift])),
        .init(command: .loupe, title: "Show or Hide Loupe", contexts: [.viewer],
              defaultShortcut: .init("`")),
        .init(command: .lift, title: "Lift Settings", contexts: allContexts,
              defaultShortcut: .init("c", modifiers: [.command, .shift])),
        .init(command: .stamp, title: "Stamp Selected Settings", contexts: allContexts,
              defaultShortcut: .init("v", modifiers: [.command, .shift])),
        .init(command: .newVersion, title: "New Version from Original", contexts: allContexts,
              defaultShortcut: .init("g", modifiers: [.option])),
        .init(command: .duplicateVersion, title: "Duplicate Version", contexts: allContexts,
              defaultShortcut: .init("v", modifiers: [.option])),
        .init(command: .batchChange, title: "Batch Change", contexts: [.browser, .viewer],
              defaultShortcut: .init("b", modifiers: [.command, .shift])),
        .init(command: .rating0, title: "Set Unrated", contexts: allContexts, defaultShortcut: .init("0")),
        .init(command: .rating1, title: "Set 1 Star", contexts: allContexts, defaultShortcut: .init("1")),
        .init(command: .rating2, title: "Set 2 Stars", contexts: allContexts, defaultShortcut: .init("2")),
        .init(command: .rating3, title: "Set 3 Stars", contexts: allContexts, defaultShortcut: .init("3")),
        .init(command: .rating4, title: "Set 4 Stars", contexts: allContexts, defaultShortcut: .init("4")),
        .init(command: .rating5, title: "Set 5 Stars", contexts: allContexts, defaultShortcut: .init("5")),
        .init(command: .reject, title: "Reject Photos", contexts: allContexts, defaultShortcut: .init("9")),
        .init(command: .raiseRating, title: "Raise Rating", contexts: allContexts, defaultShortcut: .init("=")),
        .init(command: .lowerRating, title: "Lower Rating", contexts: allContexts, defaultShortcut: .init("-")),
        .init(command: .flag, title: "Flag or Unflag Photos", contexts: allContexts, defaultShortcut: .init("/")),
        .init(command: .previousPhoto, title: "Previous Photo", contexts: allContexts, defaultShortcut: .init("left")),
        .init(command: .nextPhoto, title: "Next Photo", contexts: allContexts, defaultShortcut: .init("right")),
    ]

    static let byCommand = Dictionary(uniqueKeysWithValues: definitions.map { ($0.command, $0) })
}

struct KeyboardCommandSet: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var bindings: [String: KeyboardCommandShortcut]
    var disabledCommands: Set<String>

    init(id: String = UUID().uuidString, name: String,
         bindings: [String: KeyboardCommandShortcut] = [:], disabledCommands: Set<String> = []) {
        self.id = id
        self.name = name
        self.bindings = bindings
        self.disabledCommands = disabledCommands
    }

    private enum CodingKeys: String, CodingKey { case id, name, bindings, disabledCommands }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        bindings = try values.decodeIfPresent([String: KeyboardCommandShortcut].self, forKey: .bindings) ?? [:]
        disabledCommands = try values.decodeIfPresent(Set<String>.self, forKey: .disabledCommands) ?? []
    }
}

enum KeyboardCommandPreferencesError: LocalizedError, Equatable {
    case builtInSet
    case invalidShortcut
    case conflict(String)
    case invalidImport

    var errorDescription: String? {
        switch self {
        case .builtInSet: return "Create a named command set before changing shortcuts."
        case .invalidShortcut: return "Choose a supported key."
        case .conflict(let title): return "This shortcut conflicts with \(title)."
        case .invalidImport: return "The command set is invalid or contains conflicting shortcuts."
        }
    }
}

struct KeyboardCommandPreferences: Codable, Equatable {
    static let key = "keyboard.commandSets.v1"
    static let defaultSetID = "isonique-default"
    var version = 1
    var activeSetID = defaultSetID
    var sets: [KeyboardCommandSet] = [.init(id: defaultSetID, name: "Isonique Default")]

    private enum CodingKeys: String, CodingKey { case version, activeSetID, sets }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        activeSetID = try values.decodeIfPresent(String.self, forKey: .activeSetID) ?? Self.defaultSetID
        sets = try values.decodeIfPresent([KeyboardCommandSet].self, forKey: .sets) ??
            [.init(id: Self.defaultSetID, name: "Isonique Default")]
        if !sets.contains(where: { $0.id == Self.defaultSetID }) {
            sets.insert(.init(id: Self.defaultSetID, name: "Isonique Default"), at: 0)
        }
        if !sets.contains(where: { $0.id == activeSetID }) { activeSetID = Self.defaultSetID }
    }

    var activeSet: KeyboardCommandSet {
        sets.first { $0.id == activeSetID } ?? sets[0]
    }

    func shortcut(for command: IsoniqueKeyboardCommand, in set: KeyboardCommandSet? = nil) -> KeyboardCommandShortcut? {
        let set = set ?? activeSet
        if set.disabledCommands.contains(command.rawValue) { return nil }
        if let shortcut = set.bindings[command.rawValue] { return shortcut }
        return KeyboardCommandDefinition.byCommand[command]?.defaultShortcut
    }

    mutating func select(_ id: String) {
        if sets.contains(where: { $0.id == id }) { activeSetID = id }
    }

    @discardableResult
    mutating func createSet(named proposedName: String, copying source: KeyboardCommandSet? = nil) -> String {
        let name = uniqueName(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? "Custom Commands" : proposedName)
        let source = source ?? activeSet
        var bindings: [String: KeyboardCommandShortcut] = [:]
        var disabled: Set<String> = []
        for definition in KeyboardCommandDefinition.definitions {
            if let shortcut = shortcut(for: definition.command, in: source) {
                bindings[definition.command.rawValue] = shortcut
            } else {
                disabled.insert(definition.command.rawValue)
            }
        }
        let set = KeyboardCommandSet(name: name, bindings: bindings, disabledCommands: disabled)
        sets.append(set)
        activeSetID = set.id
        return set.id
    }

    mutating func renameActive(_ proposedName: String) throws {
        guard activeSetID != Self.defaultSetID,
              let index = sets.firstIndex(where: { $0.id == activeSetID }) else {
            throw KeyboardCommandPreferencesError.builtInSet
        }
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sets[index].name = uniqueName(trimmed, excluding: activeSetID)
    }

    mutating func deleteActive() throws {
        guard activeSetID != Self.defaultSetID else { throw KeyboardCommandPreferencesError.builtInSet }
        sets.removeAll { $0.id == activeSetID }
        activeSetID = Self.defaultSetID
    }

    mutating func resetActive() throws {
        guard activeSetID != Self.defaultSetID,
              let index = sets.firstIndex(where: { $0.id == activeSetID }) else {
            throw KeyboardCommandPreferencesError.builtInSet
        }
        sets[index].bindings = [:]
        sets[index].disabledCommands = []
    }

    mutating func setShortcut(_ shortcut: KeyboardCommandShortcut?,
                              for command: IsoniqueKeyboardCommand) throws {
        guard activeSetID != Self.defaultSetID,
              let index = sets.firstIndex(where: { $0.id == activeSetID }) else {
            throw KeyboardCommandPreferencesError.builtInSet
        }
        if let shortcut {
            guard shortcut.isValid else { throw KeyboardCommandPreferencesError.invalidShortcut }
            if let conflict = conflict(for: command, shortcut: shortcut, in: sets[index]) {
                throw KeyboardCommandPreferencesError.conflict(conflict)
            }
            sets[index].bindings[command.rawValue] = shortcut
            sets[index].disabledCommands.remove(command.rawValue)
        } else {
            sets[index].bindings.removeValue(forKey: command.rawValue)
            sets[index].disabledCommands.insert(command.rawValue)
        }
    }

    func conflict(for command: IsoniqueKeyboardCommand, shortcut: KeyboardCommandShortcut,
                  in set: KeyboardCommandSet? = nil) -> String? {
        guard let definition = KeyboardCommandDefinition.byCommand[command] else { return nil }
        for reserved in Self.reservedShortcuts where reserved.shortcut == shortcut &&
            !reserved.contexts.isDisjoint(with: definition.contexts) {
            return reserved.title
        }
        let set = set ?? activeSet
        for other in KeyboardCommandDefinition.definitions where other.command != command &&
            !other.contexts.isDisjoint(with: definition.contexts) && self.shortcut(for: other.command, in: set) == shortcut {
            return other.localizedTitle
        }
        return nil
    }

    func validated() throws -> Self {
        guard !sets.isEmpty, sets.contains(where: { $0.id == Self.defaultSetID }),
              sets.contains(where: { $0.id == activeSetID }) else {
            throw KeyboardCommandPreferencesError.invalidImport
        }
        for set in sets {
            for definition in KeyboardCommandDefinition.definitions {
                if let shortcut = shortcut(for: definition.command, in: set) {
                    guard shortcut.isValid,
                          conflict(for: definition.command, shortcut: shortcut, in: set) == nil else {
                        throw KeyboardCommandPreferencesError.invalidImport
                    }
                }
            }
        }
        return self
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              let validated = try? decoded.validated() else { return Self() }
        return validated
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(activeSet)
    }

    mutating func importSet(from data: Data) throws {
        var imported = try JSONDecoder().decode(KeyboardCommandSet.self, from: data)
        imported.id = UUID().uuidString
        imported.name = uniqueName(imported.name)
        var trial = self
        trial.sets.append(imported)
        trial.activeSetID = imported.id
        _ = try trial.validated()
        self = trial
    }

    private func uniqueName(_ proposed: String, excluding excludedID: String? = nil) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Command Set" : proposed
        let names = Set(sets.filter { $0.id != excludedID }.map { $0.name.lowercased() })
        if !names.contains(base.lowercased()) { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private struct ReservedShortcut {
        let title: String
        let shortcut: KeyboardCommandShortcut
        let contexts: Set<KeyboardCommandContext>
    }

    private static let reservedShortcuts: [ReservedShortcut] = {
        let all = KeyboardCommandDefinition.allContexts
        var values: [ReservedShortcut] = [
            .init(title: "Native Full Screen", shortcut: .init("f", modifiers: [.command, .control]), contexts: all),
            .init(title: "Close Window", shortcut: .init("w", modifiers: [.command]), contexts: all),
            .init(title: "Settings", shortcut: .init(",", modifiers: [.command]), contexts: all),
            .init(title: "Undo", shortcut: .init("z", modifiers: [.command]), contexts: all),
            .init(title: "Redo", shortcut: .init("z", modifiers: [.command, .shift]), contexts: all),
            .init(title: "Cut", shortcut: .init("x", modifiers: [.command]), contexts: all),
            .init(title: "Copy", shortcut: .init("c", modifiers: [.command]), contexts: all),
            .init(title: "Paste", shortcut: .init("v", modifiers: [.command]), contexts: all),
            .init(title: "Select All", shortcut: .init("a", modifiers: [.command]), contexts: all),
            .init(title: "Find", shortcut: .init("f", modifiers: [.command]), contexts: all),
            .init(title: "Print", shortcut: .init("p", modifiers: [.command]), contexts: all),
            .init(title: "Import", shortcut: .init("i", modifiers: [.command]), contexts: all),
            .init(title: "Export", shortcut: .init("e", modifiers: [.command, .shift]), contexts: all),
            .init(title: "New Library", shortcut: .init("n", modifiers: [.command, .shift]), contexts: all),
            .init(title: "Stack Selected", shortcut: .init("k", modifiers: [.command]), contexts: all),
            .init(title: "Stack Pick", shortcut: .init("\\", modifiers: [.command]), contexts: all),
            .init(title: "Album Pick", shortcut: .init("\\", modifiers: [.command, .shift]), contexts: all),
            .init(title: "New Smart Album", shortcut: .init("l", modifiers: [.command, .shift]), contexts: all),
            .init(title: "Move to Trash", shortcut: .init("delete", modifiers: [.command]), contexts: all),
        ]
        for slot in 1...8 {
            values.append(.init(title: "Add Keyword \(slot)", shortcut: .init("\(slot)", modifiers: [.option]), contexts: all))
            values.append(.init(title: "Remove Keyword \(slot)", shortcut: .init("\(slot)", modifiers: [.option, .shift]), contexts: all))
        }
        for slot in 0...7 {
            values.append(.init(title: "Colour Label \(slot)", shortcut: .init("\(slot)", modifiers: [.command]), contexts: all))
        }
        return values
    }()
}

enum IsoniqueToolbarItem: String, Codable, CaseIterable, Identifiable {
    case selection
    case features
    case inspector
    case sortAndFilter
    case review
    case importPhotos
    case exportPhotos

    var id: String { rawValue }
    var title: String {
        switch self {
        case .selection: return "Select Photos"
        case .features: return "Features & Limits"
        case .inspector: return "Inspector"
        case .sortAndFilter: return "Sort & Filter"
        case .review: return "Review"
        case .importPhotos: return "Import"
        case .exportPhotos: return "Export"
        }
    }
    var localizedTitle: String { Bundle.main.localizedString(forKey: title, value: nil, table: nil) }
    static let defaultItems = allCases
}

struct IsoniqueToolbarConfiguration: Codable, Equatable {
    static let key = "toolbar.configuration.v1"
    var itemIDs = IsoniqueToolbarItem.defaultItems.map(\.rawValue)

    var items: [IsoniqueToolbarItem] {
        var seen: Set<IsoniqueToolbarItem> = []
        return itemIDs.compactMap(IsoniqueToolbarItem.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    mutating func setVisible(_ item: IsoniqueToolbarItem, visible: Bool) {
        itemIDs.removeAll { $0 == item.rawValue }
        if visible { itemIDs.append(item.rawValue) }
    }

    mutating func move(_ item: IsoniqueToolbarItem, by delta: Int) {
        guard let index = itemIDs.firstIndex(of: item.rawValue) else { return }
        let destination = min(itemIDs.count - 1, max(0, index + delta))
        guard destination != index else { return }
        let value = itemIDs.remove(at: index)
        itemIDs.insert(value, at: destination)
    }

    mutating func reset() { itemIDs = IsoniqueToolbarItem.defaultItems.map(\.rawValue) }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return decoded
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

enum KeyboardCommandRouter {
    static func command(for shortcut: KeyboardCommandShortcut,
                        context: KeyboardCommandContext,
                        preferences: KeyboardCommandPreferences,
                        textInputActive: Bool,
                        sheetActive: Bool) -> IsoniqueKeyboardCommand? {
        guard !textInputActive, !sheetActive else { return nil }
        return KeyboardCommandDefinition.definitions.first {
            $0.contexts.contains(context) && preferences.shortcut(for: $0.command) == shortcut
        }?.command
    }
}

extension Workspace {
    var activeKeyboardCommandSet: KeyboardCommandSet { commandPreferences.activeSet }

    func selectCommandSet(_ id: String) {
        commandPreferences.select(id)
        saveCommandPreferences()
    }

    func createCommandSet(named name: String) {
        commandPreferences.createSet(named: name)
        saveCommandPreferences()
    }

    func renameActiveCommandSet(_ name: String) throws {
        try commandPreferences.renameActive(name)
        saveCommandPreferences()
    }

    func deleteActiveCommandSet() throws {
        try commandPreferences.deleteActive()
        saveCommandPreferences()
    }

    func resetActiveCommandSet() throws {
        try commandPreferences.resetActive()
        saveCommandPreferences()
    }

    func setCommandShortcut(_ shortcut: KeyboardCommandShortcut?,
                            for command: IsoniqueKeyboardCommand) throws {
        try commandPreferences.setShortcut(shortcut, for: command)
        saveCommandPreferences()
    }

    func importCommandSet(_ data: Data) throws {
        try commandPreferences.importSet(from: data)
        saveCommandPreferences()
    }

    func saveToolbarConfiguration() {
        toolbarConfiguration.save(to: preferences)
    }

    func setToolbarItem(_ item: IsoniqueToolbarItem, visible: Bool) {
        toolbarConfiguration.setVisible(item, visible: visible)
        saveToolbarConfiguration()
    }

    func moveToolbarItem(_ item: IsoniqueToolbarItem, by delta: Int) {
        toolbarConfiguration.move(item, by: delta)
        saveToolbarConfiguration()
    }

    func resetToolbarConfiguration() {
        toolbarConfiguration.reset()
        saveToolbarConfiguration()
    }

    func installKeyboardCommandMonitor(for window: NSWindow) {
        if let keyboardCommandMonitor { NSEvent.removeMonitor(keyboardCommandMonitor) }
        keyboardCommandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            return self.handleKeyboardCommandEvent(event, window: window) ? nil : event
        }
    }

    func handleKeyboardCommandEvent(_ event: NSEvent, window: NSWindow) -> Bool {
        guard let shortcut = KeyboardCommandShortcut(event: event) else { return false }
        let context: KeyboardCommandContext
        if comparisonID != nil && viewer { context = .compare }
        else if viewer { context = .viewer }
        else { context = .browser }
        guard let command = KeyboardCommandRouter.command(for: shortcut, context: context,
            preferences: commandPreferences, textInputActive: window.firstResponder is NSTextView,
            sheetActive: window.attachedSheet != nil) else { return false }
        return performKeyboardCommand(command)
    }

    @discardableResult
    func performKeyboardCommand(_ command: IsoniqueKeyboardCommand) -> Bool {
        switch command {
        case .toggleBrowser: togglePhotographyPanel(.browser)
        case .toggleFilmstrip: togglePhotographyPanel(.filmstrip)
        case .toggleInspector: togglePhotographyPanel(.inspector)
        case .toggleToolbar: togglePhotographyPanel(.toolbar)
        case .cyclePanels: cyclePhotographyFocus()
        case .gridBrowser:
            guard canChoosePresentation(.grid) else { return false }
            choosePresentation(.grid)
        case .listBrowser:
            guard canChoosePresentation(.list) else { return false }
            choosePresentation(.list)
        case .places:
            guard canChoosePresentation(.places) else { return false }
            choosePresentation(.places)
        case .quickPreview:
            guard quickPreview || canToggleQuickPreview else { return false }
            toggleQuickPreview()
        case .advancedSearch:
            guard !busy, repository != nil else { return false }
            showAdvancedSearch = true
        case .startCompare:
            guard canStartComparison else { return false }
            startComparison()
        case .endCompare:
            guard comparisonID != nil else { return false }
            stopComparison()
        case .promoteCompare:
            guard canPromoteComparisonSelection else { return false }
            promoteComparisonSelection()
        case .removeCompare:
            guard canRemoveComparisonSelection else { return false }
            removeComparisonSelection()
        case .clippingWarnings:
            clipping.both.toggle()
        case .loupe:
            guard loupeActive || canShowLoupe else { return false }
            toggleLoupe()
        case .lift:
            guard canLift else { return false }
            lift()
        case .stamp:
            guard canStamp else { return false }
            stamp()
        case .newVersion:
            guard canCreateVersion else { return false }
            createVersion(from: .original)
        case .duplicateVersion:
            guard canCreateVersion else { return false }
            createVersion(from: .current)
        case .batchChange:
            guard canOpenBatchMetadata else { return false }
            openBatchMetadata()
        case .rating0: return setRatingFromCommand(0)
        case .rating1: return setRatingFromCommand(1)
        case .rating2: return setRatingFromCommand(2)
        case .rating3: return setRatingFromCommand(3)
        case .rating4: return setRatingFromCommand(4)
        case .rating5: return setRatingFromCommand(5)
        case .reject: return setRatingFromCommand(RatingRules.rejected)
        case .raiseRating:
            guard canReviewSelection else { return false }
            adjustReviewRating(by: 1)
        case .lowerRating:
            guard canReviewSelection else { return false }
            adjustReviewRating(by: -1)
        case .flag:
            guard canReviewSelection else { return false }
            toggleReviewFlag()
        case .previousPhoto: return navigateFromCommand(by: -1)
        case .nextPhoto: return navigateFromCommand(by: 1)
        }
        return true
    }

    private func setRatingFromCommand(_ rating: Int) -> Bool {
        guard canReviewSelection else { return false }
        setReviewRating(rating)
        return true
    }

    private func navigateFromCommand(by delta: Int) -> Bool {
        guard !batchMode, !reviewPhotos.isEmpty else { return false }
        if comparisonID != nil {
            moveComparisonSelection(by: delta)
            return true
        }
        let visible = reviewPhotos.filter { $0.id != comparisonID }
        if let index = visible.firstIndex(where: { $0.id == reviewSelectionID }) {
            let next = index + delta
            if visible.indices.contains(next) { reviewSelectionID = visible[next].id }
        } else {
            reviewSelectionID = visible.first?.id
        }
        return true
    }

    func exportActiveCommandSetPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(activeKeyboardCommandSet.name).isonique-commands.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try commandPreferences.exportData().write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }

    func importCommandSetPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importCommandSet(Data(contentsOf: url)) }
        catch { self.error = error.localizedDescription }
    }

    private func saveCommandPreferences() {
        commandPreferences.save(to: preferences)
    }
}

struct ToolbarConfigurationView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customize Toolbar").font(.title2.bold())
            Text("Choose the controls shown in the main window and arrange their order.")
                .foregroundStyle(.secondary)
            List {
                ForEach(IsoniqueToolbarItem.allCases) { item in
                    let visible = model.toolbarConfiguration.items.contains(item)
                    HStack {
                        Toggle(item.localizedTitle, isOn: Binding(
                            get: { model.toolbarConfiguration.items.contains(item) },
                            set: { model.setToolbarItem(item, visible: $0) }))
                        Spacer()
                        Button { model.moveToolbarItem(item, by: -1) } label: {
                            Image(systemName: "arrow.up")
                        }.disabled(!visible || model.toolbarConfiguration.items.first == item)
                        Button { model.moveToolbarItem(item, by: 1) } label: {
                            Image(systemName: "arrow.down")
                        }.disabled(!visible || model.toolbarConfiguration.items.last == item)
                    }
                }
            }
            HStack {
                Button("Reset to Defaults", action: model.resetToolbarConfiguration)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520, height: 500)
    }
}

struct KeyboardCommandEditorView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selected = IsoniqueKeyboardCommand.toggleBrowser
    @State private var key = "b"
    @State private var modifiers: Set<KeyboardCommandModifier> = [.command, .option]
    @State private var setName = ""
    @State private var error: String?

    private var activeIsBuiltIn: Bool {
        model.commandPreferences.activeSetID == KeyboardCommandPreferences.defaultSetID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Command Editor").font(.title2.bold())
            HStack {
                Picker("Command Set", selection: Binding(get: { model.commandPreferences.activeSetID },
                    set: { model.selectCommandSet($0); loadDraft() })) {
                    ForEach(model.commandPreferences.sets) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 260)
                TextField("Set name", text: $setName).disabled(activeIsBuiltIn)
                Button("Save Name") {
                    do { try model.renameActiveCommandSet(setName); error = nil }
                    catch { self.error = error.localizedDescription }
                }.disabled(activeIsBuiltIn || setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button("New Set") { model.createCommandSet(named: "Custom Commands"); setName = model.activeKeyboardCommandSet.name; loadDraft() }
                Button("Delete Set") {
                    do { try model.deleteActiveCommandSet(); setName = model.activeKeyboardCommandSet.name; loadDraft(); error = nil }
                    catch { self.error = error.localizedDescription }
                }.disabled(activeIsBuiltIn)
                Button("Reset Set") {
                    do { try model.resetActiveCommandSet(); loadDraft(); error = nil }
                    catch { self.error = error.localizedDescription }
                }.disabled(activeIsBuiltIn)
                Divider().frame(height: 18)
                Button("Import…", action: model.importCommandSetPanel)
                Button("Export…", action: model.exportActiveCommandSetPanel)
            }
            HSplitView {
                List(KeyboardCommandDefinition.definitions, selection: $selected) { definition in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.localizedTitle)
                        HStack {
                            Text(definition.contextLabel).foregroundStyle(.secondary)
                            Spacer()
                            Text(model.commandPreferences.shortcut(for: definition.command)?.displayName ?? "—")
                                .monospaced()
                        }.font(.caption)
                    }.tag(definition.command)
                }.frame(minWidth: 300)
                VStack(alignment: .leading, spacing: 14) {
                    if let definition = KeyboardCommandDefinition.byCommand[selected] {
                        Text(definition.localizedTitle).font(.headline)
                        Text("Scope: \(definition.contextLabel)").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Key", selection: $key) {
                        ForEach(KeyboardCommandShortcut.availableKeys, id: \.self) {
                            Text(KeyboardCommandShortcut.keyTitle($0)).tag($0)
                        }
                    }
                    ForEach(KeyboardCommandModifier.allCases, id: \.self) { modifier in
                        Toggle("\(modifier.symbol) \(modifier.rawValue.capitalized)", isOn: Binding(
                            get: { modifiers.contains(modifier) },
                            set: { if $0 { modifiers.insert(modifier) } else { modifiers.remove(modifier) } }))
                    }
                    HStack {
                        Button("Apply") { applyDraft() }.disabled(activeIsBuiltIn)
                        Button("Clear") {
                            do { try model.setCommandShortcut(nil, for: selected); error = nil }
                            catch { self.error = error.localizedDescription }
                        }.disabled(activeIsBuiltIn)
                    }
                    if let error { Text(error).foregroundStyle(.orange).font(.caption) }
                    Spacer()
                    Text("Shortcuts work only in their Browser, Viewer or Compare scope. Text fields, open sheets, macOS editing commands and quick-keyword slots are protected.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18).frame(minWidth: 300)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 760, height: 620)
        .onAppear { setName = model.activeKeyboardCommandSet.name; loadDraft() }
        .onChange(of: selected) { _, _ in loadDraft() }
        .onChange(of: model.commandPreferences.activeSetID) { _, _ in
            setName = model.activeKeyboardCommandSet.name
            loadDraft()
        }
    }

    private func loadDraft() {
        let shortcut = model.commandPreferences.shortcut(for: selected)
        key = shortcut?.key ?? "a"
        modifiers = shortcut?.modifiers ?? []
        error = nil
    }

    private func applyDraft() {
        do {
            try model.setCommandShortcut(.init(key, modifiers: modifiers), for: selected)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ConfiguredToolbarItemView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.openWindow) private var openWindow
    let item: IsoniqueToolbarItem

    var body: some View {
        switch item {
        case .selection:
            Toggle("Select Photos", isOn: $model.batchMode).onChange(of: model.batchMode) { _, active in
                model.batchSelection = []
                if active {
                    model.places = false
                    model.showBrowser()
                    if model.selected == nil { model.selection = model.photos.first?.id }
                }
            }.disabled(model.activeLightTable != nil || model.isPeopleGallery)
        case .features:
            Button { openWindow(id: "features") } label: { Label("Features & Limits", systemImage: "questionmark.circle") }
                .help("See available features and what is still missing")
        case .inspector:
            Button { withAnimation(.easeInOut(duration: 0.2)) { model.togglePhotographyPanel(.inspector) } } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }.help("Show or hide inspector")
        case .sortAndFilter:
            Menu {
                Picker("Sort by", selection: $model.sort) {
                    ForEach(PhotoSort.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                            .disabled(choice == .manual && !model.canManuallyOrder(model.scope))
                    }
                }
                Toggle("Descending", isOn: $model.sortDescending)
                Divider()
                Button("Advanced Search…") { model.showAdvancedSearch = true }
                Divider()
                Picker("Originals", selection: $model.originalFilter) {
                    ForEach(OriginalFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
                }
                Picker("Color Labels", selection: $model.colorFilter) {
                    Text("All labels").tag(ColorLabelFilter.all)
                    Text("No label").tag(ColorLabelFilter.unlabelled)
                    ForEach(PhotoColorLabel.allCases) { label in
                        Text(model.name(for: label)).tag(ColorLabelFilter.color(label))
                    }
                }
            } label: { Label("Sort & Filter", systemImage: "arrow.up.arrow.down") }
                .disabled(model.activeLightTable != nil || model.isPeopleGallery)
        case .review:
            Menu {
                Button("Compare Photos", action: model.startComparison).disabled(!model.canStartComparison)
                Button("New Light Table from Selection", action: model.createLightTable).disabled(!model.canCreateLightTable)
                Button("Auto Stack by Capture Time…") { model.showAutoStack = true }
                Button("Start Slideshow…", action: model.startSlideshow)
            } label: { Label("Review", systemImage: "play.rectangle") }
                .disabled(model.busy || model.isViewingTrash || model.photos.isEmpty || model.repository == nil)
        case .importPhotos:
            Button(action: model.importPanel) { Label("Import", systemImage: "square.and.arrow.down") }
        case .exportPhotos:
            Button(action: model.exportPanel) { Label("Export", systemImage: "square.and.arrow.up") }
                .disabled(model.activeLightTable != nil || model.isViewingTrash ||
                          (model.batchMode ? model.batchPhotos.isEmpty : model.selected == nil))
        }
    }
}
