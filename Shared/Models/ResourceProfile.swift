import Foundation

enum ResourceMode: String, CaseIterable, Identifiable, Codable {
    case austerity
    case saver
    case balanced
    case performance

    var id: String { rawValue }
}

/// A profile intentionally stores user-adjustable operating-context settings only.
/// Runtime permission state, usage history, observed apps and transient session state
/// are not part of a profile.
struct NeManeemProfileSnapshot: Codable, Equatable {
    var resourceMode: String
    var austerityKeepTotalHistory: Bool
    var expertFeaturesEnabled: Bool

    var refreshIntervalSeconds: Double
    var popoverRefreshIntervalSeconds: Double
    var popoverUseMenuBarRefresh: Bool
    var popoverClosedDataRetentionSeconds: Double
    var monitorRefreshIntervalSeconds: Double
    /// Optional keeps existing saved profiles decodable. Before Build 109, an
    /// independent monitor always used its own stored interval.
    var monitorUseMenuBarRefresh: Bool?

    var showDownload: Bool
    var showUpload: Bool
    var metricOrder: String
    var menuDisplayStyle: String
    var showIcons: Bool
    var unitMode: String

    var popoverScale: String
    var popoverUnitMode: String
    var popoverProcessDisplay: String
    var popoverDirectionDisplay: String
    var popoverSortMode: String
    var popoverColumns: [String]

    var monitorUsePopoverSettings: Bool
    var monitorScale: String
    var monitorUnitMode: String
    var monitorProcessDisplay: String
    var monitorDirectionDisplay: String
    var monitorSortMode: String
    var monitorColumns: [String]
    var alwaysOnTopMonitor: Bool
    var monitorShowTotalSpeed: Bool
    var monitorShowNetwork: Bool
    var monitorShowData: Bool

    var recordingMode: String
    var processDetailRecordingEnabled: Bool
    var separateLocalTraffic: Bool
    var safariNetworkServiceGroupingEnabled: Bool?
    var localTrafficStatisticsMode: String
    var menuBarTrafficScope: String

    var dataLimitEnabled: Bool
    var dataLimitTrafficScope: String
    var dataLimitNetworkTargetMode: String
    var dataLimitNetworkIdentifier: String
    var dataLimitNetworkDisplayName: String
    var dataLimitValue: Double
    var dataLimitUnit: String
    var dataLimitPeriodMode: String
    var dataLimitPeriodValue: Int
    var dataLimitPeriodUnit: String
    var dataLimitEndBehavior: String
    var dataLimitReachedAction: String
    var showDataLimitInPopover: Bool

    @MainActor
    static func capture(_ settings: SettingsStore) -> Self {
        Self(resourceMode: settings.resourceMode.rawValue,
             austerityKeepTotalHistory: settings.austerityKeepTotalHistory,
             expertFeaturesEnabled: settings.expertFeaturesEnabled,
             refreshIntervalSeconds: settings.refreshIntervalSeconds,
             popoverRefreshIntervalSeconds: settings.popoverRefreshIntervalSeconds,
             popoverUseMenuBarRefresh: settings.popoverUseMenuBarRefresh,
             popoverClosedDataRetentionSeconds: settings.popoverClosedDataRetentionSeconds,
             monitorRefreshIntervalSeconds: settings.monitorRefreshIntervalSeconds,
             monitorUseMenuBarRefresh: settings.monitorUseMenuBarRefresh,
             showDownload: settings.showDownload,
             showUpload: settings.showUpload,
             metricOrder: settings.metricOrder.rawValue,
             menuDisplayStyle: settings.menuDisplayStyle.rawValue,
             showIcons: settings.showIcons,
             unitMode: settings.unitMode.rawValue,
             popoverScale: settings.popoverScale.rawValue,
             popoverUnitMode: settings.popoverUnitMode.rawValue,
             popoverProcessDisplay: settings.popoverProcessDisplay.rawValue,
             popoverDirectionDisplay: settings.popoverDirectionDisplay.rawValue,
             popoverSortMode: settings.popoverSortMode.rawValue,
             popoverColumns: settings.popoverColumns.map(\.rawValue),
             monitorUsePopoverSettings: settings.monitorUsePopoverSettings,
             monitorScale: settings.monitorScale.rawValue,
             monitorUnitMode: settings.monitorUnitMode.rawValue,
             monitorProcessDisplay: settings.monitorProcessDisplay.rawValue,
             monitorDirectionDisplay: settings.monitorDirectionDisplay.rawValue,
             monitorSortMode: settings.monitorSortMode.rawValue,
             monitorColumns: settings.monitorColumns.map(\.rawValue),
             alwaysOnTopMonitor: settings.alwaysOnTopMonitor,
             monitorShowTotalSpeed: settings.monitorShowTotalSpeed,
             monitorShowNetwork: settings.monitorShowNetwork,
             monitorShowData: settings.monitorShowData,
             recordingMode: settings.recordingMode.rawValue,
             processDetailRecordingEnabled: settings.processDetailRecordingEnabled,
             separateLocalTraffic: settings.separateLocalTraffic,
             safariNetworkServiceGroupingEnabled: settings.safariNetworkServiceGroupingEnabled,
             localTrafficStatisticsMode: settings.localTrafficStatisticsMode.rawValue,
             menuBarTrafficScope: settings.menuBarTrafficScope.rawValue,
             dataLimitEnabled: settings.dataLimitEnabled,
             dataLimitTrafficScope: settings.dataLimitTrafficScope.rawValue,
             dataLimitNetworkTargetMode: settings.dataLimitNetworkTargetMode.rawValue,
             dataLimitNetworkIdentifier: settings.dataLimitNetworkIdentifier,
             dataLimitNetworkDisplayName: settings.dataLimitNetworkDisplayName,
             dataLimitValue: settings.dataLimitValue,
             dataLimitUnit: settings.dataLimitUnit.rawValue,
             dataLimitPeriodMode: settings.dataLimitPeriodMode.rawValue,
             dataLimitPeriodValue: settings.dataLimitPeriodValue,
             dataLimitPeriodUnit: settings.dataLimitPeriodUnit.rawValue,
             dataLimitEndBehavior: settings.dataLimitEndBehavior.rawValue,
             dataLimitReachedAction: settings.dataLimitReachedAction.rawValue,
             showDataLimitInPopover: settings.showDataLimitInPopover)
    }

    @MainActor
    func apply(to settings: SettingsStore) {
        settings.resourceMode = ResourceMode(rawValue: resourceMode) ?? .balanced
        settings.austerityKeepTotalHistory = austerityKeepTotalHistory
        settings.expertFeaturesEnabled = expertFeaturesEnabled

        settings.refreshIntervalSeconds = SettingsStore.normalizeInterval(refreshIntervalSeconds)
        settings.popoverRefreshIntervalSeconds = SettingsStore.normalizeInterval(popoverRefreshIntervalSeconds)
        settings.popoverUseMenuBarRefresh = popoverUseMenuBarRefresh
        settings.popoverClosedDataRetentionSeconds = SettingsStore.normalizeClosedDataRetention(popoverClosedDataRetentionSeconds)
        settings.monitorRefreshIntervalSeconds = SettingsStore.normalizeInterval(monitorRefreshIntervalSeconds)
        if let monitorUseMenuBarRefresh {
            settings.monitorUseMenuBarRefresh = monitorUseMenuBarRefresh
        }

        settings.showDownload = showDownload
        settings.showUpload = showUpload
        settings.metricOrder = MenuMetricOrder(rawValue: metricOrder) ?? .downloadFirst
        settings.menuDisplayStyle = MenuDisplayStyle(rawValue: menuDisplayStyle) ?? .twoLineCompact
        settings.showIcons = showIcons
        settings.unitMode = SpeedUnitMode(rawValue: unitMode) ?? .compactBytes

        settings.popoverScale = PopoverScale(rawValue: popoverScale) ?? .standard
        settings.popoverUnitMode = SpeedUnitMode(rawValue: popoverUnitMode) ?? .bytesPerSecond
        settings.popoverProcessDisplay = ProcessDisplayMode(rawValue: popoverProcessDisplay) ?? .iconAndName
        settings.popoverDirectionDisplay = TransferDirectionDisplay(rawValue: popoverDirectionDisplay) ?? .words
        settings.popoverSortMode = TrafficSortMode(rawValue: popoverSortMode) ?? .currentUsage
        settings.popoverColumns = Self.columns(popoverColumns)

        settings.monitorUsePopoverSettings = monitorUsePopoverSettings
        settings.monitorScale = PopoverScale(rawValue: monitorScale) ?? .standard
        settings.monitorUnitMode = SpeedUnitMode(rawValue: monitorUnitMode) ?? .bytesPerSecond
        settings.monitorProcessDisplay = ProcessDisplayMode(rawValue: monitorProcessDisplay) ?? .iconAndName
        settings.monitorDirectionDisplay = TransferDirectionDisplay(rawValue: monitorDirectionDisplay) ?? .words
        settings.monitorSortMode = TrafficSortMode(rawValue: monitorSortMode) ?? .currentUsage
        settings.monitorColumns = Self.columns(monitorColumns)
        settings.alwaysOnTopMonitor = alwaysOnTopMonitor
        settings.monitorShowTotalSpeed = monitorShowTotalSpeed
        settings.monitorShowNetwork = monitorShowNetwork
        settings.monitorShowData = monitorShowData

        settings.recordingMode = RecordingMode(rawValue: recordingMode) ?? .off
        settings.processDetailRecordingEnabled = processDetailRecordingEnabled
        settings.separateLocalTraffic = separateLocalTraffic
        if let safariNetworkServiceGroupingEnabled {
            settings.safariNetworkServiceGroupingEnabled = safariNetworkServiceGroupingEnabled
        }
        settings.localTrafficStatisticsMode = LocalTrafficStatisticsMode(rawValue: localTrafficStatisticsMode) ?? .separate
        settings.menuBarTrafficScope = MenuBarTrafficScope(rawValue: menuBarTrafficScope) ?? .allTraffic

        settings.dataLimitEnabled = dataLimitEnabled
        settings.dataLimitTrafficScope = DataLimitTrafficScope(rawValue: dataLimitTrafficScope) ?? .internetOnly
        settings.dataLimitNetworkTargetMode = DataLimitNetworkTargetMode(rawValue: dataLimitNetworkTargetMode) ?? .allNetworks
        settings.dataLimitNetworkIdentifier = dataLimitNetworkIdentifier
        settings.dataLimitNetworkDisplayName = dataLimitNetworkDisplayName
        settings.dataLimitValue = dataLimitValue
        settings.dataLimitUnit = DataLimitUnit(rawValue: dataLimitUnit) ?? .gigabytes
        settings.dataLimitPeriodMode = DataLimitPeriodMode(rawValue: dataLimitPeriodMode) ?? .duration
        settings.dataLimitPeriodValue = max(1, dataLimitPeriodValue)
        settings.dataLimitPeriodUnit = DataLimitPeriodUnit(rawValue: dataLimitPeriodUnit) ?? .months
        settings.dataLimitEndBehavior = DataLimitEndBehavior(rawValue: dataLimitEndBehavior) ?? .repeatSame
        settings.dataLimitReachedAction = DataLimitReachedAction(rawValue: dataLimitReachedAction) ?? .continueData
        settings.showDataLimitInPopover = showDataLimitInPopover
    }

    private static func columns(_ raw: [String]) -> [StatusColumn] {
        var values = raw.compactMap(StatusColumn.init(rawValue:))
        if values.isEmpty { values = StatusColumn.defaultColumns }
        if !values.contains(.process) { values.insert(.process, at: 0) }
        return values
    }
}

struct NeManeemProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var showInQuickLaunch: Bool
    var snapshot: NeManeemProfileSnapshot

    init(id: UUID = UUID(), name: String, showInQuickLaunch: Bool = true, snapshot: NeManeemProfileSnapshot) {
        self.id = id
        self.name = name
        self.showInQuickLaunch = showInQuickLaunch
        self.snapshot = snapshot
    }
}

@MainActor
extension SettingsStore {
    var matchingProfile: NeManeemProfile? {
        let current = NeManeemProfileSnapshot.capture(self)
        return profiles.first { $0.snapshot == current }
    }

    func saveCurrentProfile(name: String, showInQuickLaunch: Bool = true) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let snapshot = NeManeemProfileSnapshot.capture(self)
        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            profiles[index].snapshot = snapshot
            profiles[index].showInQuickLaunch = showInQuickLaunch
        } else {
            profiles.append(NeManeemProfile(name: trimmed, showInQuickLaunch: showInQuickLaunch, snapshot: snapshot))
        }
    }

    func updateProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].snapshot = NeManeemProfileSnapshot.capture(self)
    }

    func applyProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        profile.snapshot.apply(to: self)
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
    }

    func moveProfile(id: UUID, offset: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard profiles.indices.contains(destination) else { return }
        profiles.swapAt(index, destination)
    }
}
