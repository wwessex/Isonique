import Foundation

@MainActor
enum AppPreferencesMigration {
    private static let completionKey = "migration.bundleIdentifier.v1"

    static func migrateForCurrentApp() {
        guard let currentDomain = Bundle.main.bundleIdentifier,
              currentDomain == "io.github.wwessex.isonique" else { return }
        migrate(from: "local.craftanything.isonique", to: currentDomain)
    }

    static func migrate(from previousDomain: String, to currentDomain: String) {
        let defaults = UserDefaults.standard
        let current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[completionKey] as? Bool != true else { return }

        let previous = defaults.persistentDomain(forName: previousDomain) ?? [:]
        var migrated = previous.merging(current) { _, currentValue in currentValue }
        // Store the settings and marker together so a later launch can safely retry.
        migrated[completionKey] = true
        defaults.setPersistentDomain(migrated, forName: currentDomain)
    }
}
