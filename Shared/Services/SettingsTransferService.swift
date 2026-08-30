import AppKit
import Foundation
import UniformTypeIdentifiers

enum SettingsTransferSection: String, CaseIterable, Identifiable, Codable {
    case general
    case menuBar
    case statusWindows
    case networkBehavior
    case usagePreferences
    case dataLimit
    case observedApps
    case appPreferences
    case networkIdentifiers

    var id: String { rawValue }

    var isPersonalInfoGroup: Bool {
        switch self {
        case .observedApps, .appPreferences, .networkIdentifiers: return true
        default: return false
        }
    }
}

struct SettingsBackupPreview: Identifiable {
    let id = UUID()
    let url: URL
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String
    let createdAt: Date
    let sections: Set<SettingsTransferSection>
    fileprivate let values: [String: Any]
}

enum SettingsTransferError: LocalizedError {
    case invalidFile
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "This is not a valid NeManeem settings file."
        case .unsupportedSchema(let version): return "This settings file uses an unsupported schema (\(version))."
        }
    }
}

enum SettingsTransferService {
    /// Process-local marker only. It is intentionally not persisted: after a user
    /// chooses clean removal, AppDelegate must not recreate lifecycle UserDefaults
    /// while terminating the same process.
    private(set) static var persistentDataClearedForRemoval = false
    static let schemaVersion = 1
    static let fileExtension = "nemaneem-settings"

    static var standardSections: Set<SettingsTransferSection> {
        Set(SettingsTransferSection.allCases.filter { !$0.isPersonalInfoGroup })
    }

    static var personalSections: Set<SettingsTransferSection> {
        Set(SettingsTransferSection.allCases.filter { $0.isPersonalInfoGroup })
    }

    @MainActor
    static func exportSettings(sections: Set<SettingsTransferSection>) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "NeManeem Settings"
        panel.nameFieldStringValue = "NeManeem Settings.\(fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, var destination = panel.url else { return nil }
        if destination.pathExtension.lowercased() != fileExtension {
            destination.appendPathExtension(fileExtension)
        }

        let defaults = UserDefaults.standard.dictionaryRepresentation()
        let selectedKeys = sections.reduce(into: Set<String>()) { result, section in
            result.formUnion(keys(for: section, availableKeys: Set(defaults.keys)))
        }
        var values: [String: Any] = [:]
        for key in selectedKeys {
            if let value = defaults[key] { values[key] = value }
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let root: [String: Any] = [
            "format": "NeManeemSettings",
            "schemaVersion": schemaVersion,
            "appVersion": version,
            "appBuild": build,
            "createdAt": Date(),
            "sections": sections.map(\.rawValue).sorted(),
            "containsAppOrNetworkIdentity": sections.contains(where: { $0.isPersonalInfoGroup }),
            "values": values
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    @MainActor
    static func chooseImportFile() throws -> SettingsBackupPreview? {
        let panel = NSOpenPanel()
        panel.title = "NeManeem Settings"
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try loadPreview(url: url)
    }

    static func loadPreview(url: URL) throws -> SettingsBackupPreview {
        let data = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              root["format"] as? String == "NeManeemSettings",
              let schema = root["schemaVersion"] as? Int,
              let values = root["values"] as? [String: Any] else {
            throw SettingsTransferError.invalidFile
        }
        guard schema <= schemaVersion else { throw SettingsTransferError.unsupportedSchema(schema) }
        let rawSections = root["sections"] as? [String] ?? []
        let sections = Set(rawSections.compactMap(SettingsTransferSection.init(rawValue:)))
        return SettingsBackupPreview(url: url,
                                     schemaVersion: schema,
                                     appVersion: root["appVersion"] as? String ?? "?",
                                     appBuild: root["appBuild"] as? String ?? "?",
                                     createdAt: root["createdAt"] as? Date ?? Date.distantPast,
                                     sections: sections,
                                     values: values)
    }

    static func importSettings(_ preview: SettingsBackupPreview, sections: Set<SettingsTransferSection>) {
        let allowedKeys = sections.reduce(into: Set<String>()) { result, section in
            result.formUnion(keys(for: section, availableKeys: Set(preview.values.keys)))
        }
        let defaults = UserDefaults.standard
        for key in allowedKeys {
            guard let value = preview.values[key] else { continue }
            defaults.set(value, forKey: key)
        }
    }

    static func resetSettingsDefaults() {
        resetSettings(sections: standardSections)
    }

    static func resetSettings(sections: Set<SettingsTransferSection>) {
        let defaults = UserDefaults.standard
        let available = Set(defaults.dictionaryRepresentation().keys)
        var keysToRemove = sections.reduce(into: Set<String>()) { result, section in
            result.formUnion(keys(for: section, availableKeys: available))
        }

        // Export/import intentionally omit state that must never reactivate silently
        // on another Mac. A user-requested reset is different: when the matching
        // category is selected it must actually return optional features to their
        // safe OFF/default state without deleting usage-history files.
        if sections.contains(.dataLimit) {
            keysToRemove.formUnion([
                "data.limitEnabled",
                "data.limitNetworkIdentifier",
                "data.limitNetworkDisplayName"
            ])
        }
        if sections.contains(.usagePreferences) {
            keysToRemove.formUnion([
                "data.sessionEnabled",
                "data.sessionStartDate",
                "data.sessionStartMode",
                "data.scheduledSessionStartDate",
                "data.sessionFollowsDataRenewal",
                "data.showSessionInPopover"
            ])
        }
        // Window geometry is user-facing settings state too. Resetting General
        // restores the Settings window frame; resetting Status Windows restores the
        // Monitor window frame. NSWindow autosave stores size and position together.
        if sections.contains(.general) {
            keysToRemove.insert("NSWindow Frame NeManeemSettingsWindowFrame")
        }
        if sections.contains(.statusWindows) {
            keysToRemove.insert("NSWindow Frame NeManeemMonitorWindowFrameCompactV2")
        }
        keysToRemove.forEach { defaults.removeObject(forKey: $0) }
    }

    static func clearAppPreferenceDefaults() {
        let defaults = UserDefaults.standard
        let available = Set(defaults.dictionaryRepresentation().keys)
        keys(for: .appPreferences, availableKeys: available).forEach { defaults.removeObject(forKey: $0) }
    }

    static func clearNetworkIdentifiers() {
        let defaults = UserDefaults.standard
        let available = Set(defaults.dictionaryRepresentation().keys)
        keys(for: .networkIdentifiers, availableKeys: available).forEach { defaults.removeObject(forKey: $0) }
    }

    static func clearTemporaryDiagnosticReports() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NeManeemDiagnostics", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    /// Removes only data owned and persisted by NeManeem. macOS-managed permission
    /// databases, System Extension approval state, user-exported backup files and
    /// unrelated system logs are deliberately outside this scope.
    static func clearAllAppManagedPersistentDataForRemoval() -> Error? {
        clearTemporaryDiagnosticReports()

        let fileManager = FileManager.default
        var firstError: Error?
        func removeIfPresent(_ url: URL) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let supportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            removeIfPresent(supportRoot.appendingPathComponent("NeManeem", isDirectory: true))
        }
        if let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            removeIfPresent(cachesRoot.appendingPathComponent("NeManeem", isDirectory: true))
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            persistentDataClearedForRemoval = true
        }
        return firstError
    }

    private static func keys(for section: SettingsTransferSection, availableKeys: Set<String>) -> Set<String> {
        switch section {
        case .general:
            return availableKeys.filter { key in
                key == "appearance" || key.hasPrefix("appearance.") || key == "language" || key.hasPrefix("general.")
            }
        case .menuBar:
            return availableKeys.filter { $0.hasPrefix("menu.") || $0 == "monitor.refreshIntervalSeconds" || $0 == "monitor.useMenuBarRefresh" || $0 == "refresh.defaultsVersion" }
        case .statusWindows:
            return availableKeys.filter { key in
                let isStatus = key.hasPrefix("popover.") || key.hasPrefix("monitor.") || key.hasPrefix("monitorWindow.") || key.hasPrefix("status.")
                return isStatus && key != "monitor.refreshIntervalSeconds" && key != "monitor.useMenuBarRefresh" && !isAppPreferenceKey(key)
            }
        case .networkBehavior:
            return availableKeys.filter { key in
                key == "network.separateLocalTraffic" || key == "network.safariNetworkServiceGroupingEnabled" || key == "network.localTrafficStatisticsMode" || key == "network.dataLimitTrafficScope" || key == "network.menuBarTrafficScope"
            }
        case .usagePreferences:
            return availableKeys.filter { key in
                key.hasPrefix("history.") || key == "data.showSessionInPopover"
            }
        case .dataLimit:
            return availableKeys.filter { key in
                guard key.hasPrefix("data.") else { return false }
                if key.hasPrefix("data.session") || key == "data.showSessionInPopover" { return false }
                if key == "data.limitNetworkIdentifier" || key == "data.limitNetworkDisplayName" { return false }
                // Importing settings must never silently resume a data-limit guard on
                // a new Mac without the old machine's usage history.
                if key == "data.limitEnabled" { return false }
                return true
            }
        case .observedApps:
            return availableKeys.filter { $0 == "network.observedProcessIDs" || $0 == "network.observedCatalogV1" }
        case .appPreferences:
            return availableKeys.filter { isAppPreferenceKey($0) || $0 == "firewall.blockedBundleIdentifiers" || $0 == "firewall.blockedProcessIdentifiers" || $0 == "firewall.processBlockingEnabled" }
        case .networkIdentifiers:
            return availableKeys.filter { $0 == "data.limitNetworkIdentifier" || $0 == "data.limitNetworkDisplayName" }
        }
    }

    private static func isAppPreferenceKey(_ key: String) -> Bool {
        let suffixes = ["manualOrder", "hiddenProcessIDs", "selectedProcessIDs", "orderPresets"]
        if suffixes.contains(where: { key.hasSuffix($0) }) { return true }
        return key == "status.hiddenDetailProcessIDs"
    }
}
