import Combine
import Foundation

enum TrafficDirection: String, CaseIterable, Identifiable {
    case download
    case upload
    var id: String { rawValue }
    var shortSymbol: String { self == .download ? "↓" : "↑" }
}

enum MenuMetricOrder: String, CaseIterable, Identifiable {
    case downloadFirst
    case uploadFirst
    var id: String { rawValue }
}

/// Retained only to decode settings/profile files created before the free-layout
/// menu bar replaced the old three-style selector. It is intentionally not
/// exposed in the current UI and should not drive new rendering decisions.
enum LegacyMenuDisplayStyle: String, CaseIterable, Identifiable {
    case twoLineCompact
    case oneLineCompact
    case oneLineLarge
    var id: String { rawValue }
}

/// Independent blocks that can be freely composed in the menu bar.
/// Arrows and values are intentionally separate so users can place arrows before
/// or after their corresponding numbers. Two row arrays form a two-line layout;
/// leaving the lower row empty produces a one-line layout.
enum MenuBarElement: String, CaseIterable, Identifiable, Codable {
    case uploadArrow
    case uploadValue
    case downloadArrow
    case downloadValue
    case limitValue
    case limitPercent
    case limitLight

    var id: String { rawValue }
    var isLimitElement: Bool {
        switch self {
        case .limitValue, .limitPercent, .limitLight: return true
        default: return false
        }
    }

    static let defaultTop: [MenuBarElement] = [.uploadArrow, .uploadValue]
    static let defaultBottom: [MenuBarElement] = [.downloadArrow, .downloadValue]
}

enum SpeedUnitMode: String, CaseIterable, Identifiable {
    case compactBytes
    case bytesPerSecond
    case bitsPerSecond
    var id: String { rawValue }
}

enum PopoverScale: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge
    var id: String { rawValue }
    var factor: CGFloat {
        switch self {
        case .small: return 0.88
        case .standard: return 1.0
        case .large: return 1.16
        case .extraLarge: return 1.32
        }
    }
}

enum ProcessDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case nameOnly
    case iconAndName
    var id: String { rawValue }
}

enum TransferDirectionDisplay: String, CaseIterable, Identifiable {
    case words
    case arrows
    var id: String { rawValue }
}

enum TrafficSortMode: String, CaseIterable, Identifiable {
    case currentUsage
    case download
    case upload
    case name
    case manual
    var id: String { rawValue }
}

enum AppVisibilityMode: String, CaseIterable, Identifiable {
    case allApps
    case selectedOnly
    var id: String { rawValue }
}

/// Display unit for the low-activity threshold. The stored threshold remains
/// normalized in KB/s so changing only the display unit never changes meaning.
enum LowActivityRateUnit: String, CaseIterable, Identifiable {
    case bytesPerSecond = "B/s"
    case kilobytesPerSecond = "KB/s"
    case megabytesPerSecond = "MB/s"

    var id: String { rawValue }
}

/// 0.4 Build 46 replaces the old instantaneous low-activity rate test with a
/// calm time-window test: "N minutes/hours 동안 M KB/MB/GB 이하".
enum LowActivityDurationUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    var id: String { rawValue }
    var secondsMultiplier: Double { self == .minutes ? 60 : 3600 }
}

enum LowActivityDataUnit: String, CaseIterable, Identifiable {
    case kilobytes = "KB"
    case megabytes = "MB"
    case gigabytes = "GB"
    var id: String { rawValue }
    var byteMultiplier: Double {
        switch self {
        case .kilobytes: return 1_000
        case .megabytes: return 1_000_000
        case .gigabytes: return 1_000_000_000
        }
    }
}

/// Columns that can be composed horizontally in Popover/Monitor status tables.
/// Process is always required; every other column is optional and reorderable.
enum StatusColumn: String, CaseIterable, Identifiable, Codable {
    case process
    case download
    case upload
    case today
    case week
    case month
    case session
    case dataCycle
    case allowed = "block"

    var id: String { rawValue }
    static let defaultColumns: [StatusColumn] = [.process, .download, .upload, .allowed]
}

/// A configured column can remain in the user's layout while its backing feature is off.
/// Rendering filters those temporarily unavailable columns without mutating the saved order.
func activeStatusColumns(_ columns: [StatusColumn], appBlockingEnabled: Bool) -> [StatusColumn] {
    let source = columns.isEmpty ? StatusColumn.defaultColumns : columns
    let filtered = source.filter { $0 != .allowed || appBlockingEnabled }
    return filtered.isEmpty ? [.process] : filtered
}

enum DataRenewalMode: String, CaseIterable, Identifiable {
    case monthly
    case none
    var id: String { rawValue }
}

enum SessionStartMode: String, CaseIterable, Identifiable {
    case now
    case scheduled
    var id: String { rawValue }
}

enum SessionScheduleEndMode: String, CaseIterable, Identifiable {
    case endDate
    case duration
    var id: String { rawValue }
}

struct TrafficOrderPreset: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var order: [String]

    init(id: String = UUID().uuidString, name: String, order: [String]) {
        self.id = id
        self.name = name
        self.order = order
    }
}

enum InactiveAppPolicy: String, CaseIterable, Identifiable {
    case immediate
    case seconds3
    case seconds5
    case seconds10
    case keep
    var id: String { rawValue }

}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: String { rawValue }
}

enum AppAccentMode: String, CaseIterable, Identifiable {
    case neutral
    case system
    case custom
    var id: String { rawValue }
}

enum SettingsWindowSizeMode: String, CaseIterable, Identifiable {
    case free
    case widthFixed
    case sizeFixed
    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case korean
    case english
    case japanese
    case spanish
    var id: String { rawValue }
}

enum RecordingMode: String, CaseIterable, Identifiable {
    case off
    case total
    case perApp
    var id: String { rawValue }
}

enum DataLimitDisplayMode: String, CaseIterable, Identifiable {
    case used
    case remaining
    var id: String { rawValue }
}

enum DataLimitWarningMode: String, CaseIterable, Identifiable, Codable {
    case percentage
    case remainingAmount
    var id: String { rawValue }
}

enum DataLimitPeriodMode: String, CaseIterable, Identifiable {
    case duration
    case selectedMonthEnd
    case endDate
    var id: String { rawValue }
}

enum DataLimitPeriodUnit: String, CaseIterable, Identifiable {
    case days
    case months
    var id: String { rawValue }
}

enum DataLimitEndBehavior: String, CaseIterable, Identifiable {
    case stop
    case repeatSame
    case switchToMonthly
    var id: String { rawValue }
}

enum DataLimitReachedAction: String, CaseIterable, Identifiable {
    case continueData
    case blockInternet
    var id: String { rawValue }
}

struct DataLimitWarningRule: Codable, Identifiable, Equatable {
    var id: UUID
    var mode: DataLimitWarningMode
    var percentage: Double {
        didSet { percentage = min(99, max(1, percentage)) }
    }
    var remainingValue: Double {
        didSet { remainingValue = max(0, remainingValue) }
    }
    var remainingUnit: DataLimitUnit

    init(id: UUID = UUID(),
         mode: DataLimitWarningMode = .percentage,
         percentage: Double = 80,
         remainingValue: Double = 1,
         remainingUnit: DataLimitUnit = .gigabytes) {
        self.id = id
        self.mode = mode
        self.percentage = min(99, max(1, percentage))
        self.remainingValue = max(0, remainingValue)
        self.remainingUnit = remainingUnit
    }

    var remainingBytes: UInt64 {
        let bytes = max(0, remainingValue) * remainingUnit.byteMultiplier
        return UInt64(min(bytes, Double(UInt64.max)))
    }
}

enum DataLimitUnit: String, CaseIterable, Identifiable, Codable {
    case megabytes = "MB"
    case gigabytes = "GB"
    case terabytes = "TB"

    var id: String { rawValue }

    var byteMultiplier: Double {
        switch self {
        case .megabytes: return 1_000_000
        case .gigabytes: return 1_000_000_000
        case .terabytes: return 1_000_000_000_000
        }
    }
}


enum LocalTrafficStatisticsMode: String, CaseIterable, Identifiable {
    case separate
    case combined
    case hidden
    var id: String { rawValue }
}

enum DataLimitTrafficScope: String, CaseIterable, Identifiable {
    case internetOnly
    case allTraffic
    var id: String { rawValue }
}

enum DataLimitNetworkTargetMode: String, CaseIterable, Identifiable {
    case allNetworks
    case selectedNetwork
    var id: String { rawValue }
}

enum MenuBarTrafficScope: String, CaseIterable, Identifiable {
    case allTraffic
    case internetOnly
    var id: String { rawValue }
}

enum MainWindowMode: String {
    case standard
    case monitor
}

@MainActor
final class SettingsStore: ObservableObject {
    static let defaultMenuFontSize: Double = 9.5
    static let maximumDataLimitWarningRules = 3
    private let defaults = UserDefaults.standard

    @Published var showDownload: Bool { didSet { save(showDownload, Keys.showDownload) } }
    @Published var showUpload: Bool { didSet { save(showUpload, Keys.showUpload) } }
    @Published var metricOrder: MenuMetricOrder { didSet { save(metricOrder.rawValue, Keys.metricOrder) } }
    @Published var menuDisplayStyle: LegacyMenuDisplayStyle { didSet { save(menuDisplayStyle.rawValue, Keys.menuDisplayStyle) } }
    @Published var showIcons: Bool { didSet { save(showIcons, Keys.showIcons) } }
    @Published var menuBarTopElements: [MenuBarElement] { didSet { save(menuBarTopElements.map(\.rawValue), Keys.menuBarTopElements) } }
    @Published var menuBarBottomElements: [MenuBarElement] { didSet { save(menuBarBottomElements.map(\.rawValue), Keys.menuBarBottomElements) } }
    @Published var unitMode: SpeedUnitMode { didSet { save(unitMode.rawValue, Keys.unitMode) } }
    @Published var refreshIntervalSeconds: Double { didSet { save(normalizedInterval(refreshIntervalSeconds), Keys.refreshInterval) } }
    @Published var popoverRefreshIntervalSeconds: Double { didSet { save(normalizedInterval(popoverRefreshIntervalSeconds), Keys.popoverRefreshInterval) } }
    /// Retained compatibility key; the UI presents this as the first refresh choice.
    @Published var popoverUseMenuBarRefresh: Bool { didSet { save(popoverUseMenuBarRefresh, Keys.popoverUseMenuBarRefresh) } }
    @Published var popoverClosedDataRetentionSeconds: Double { didSet { save(Self.normalizeClosedDataRetention(popoverClosedDataRetentionSeconds), Keys.popoverClosedDataRetention) } }
    @Published var monitorRefreshIntervalSeconds: Double { didSet { save(normalizedInterval(monitorRefreshIntervalSeconds), Keys.monitorRefreshInterval) } }
    @Published var monitorUseMenuBarRefresh: Bool { didSet { save(monitorUseMenuBarRefresh, Keys.monitorUseMenuBarRefresh) } }
    @Published var appearance: AppAppearance { didSet { save(appearance.rawValue, Keys.appearance) } }
    @Published var accentMode: AppAccentMode { didSet { save(accentMode.rawValue, Keys.accentMode) } }
    @Published var customAccentHex: String { didSet { save(customAccentHex, Keys.customAccentHex) } }
    @Published var language: AppLanguage { didSet { save(language.rawValue, Keys.language) } }
    @Published var settingsWindowSizeMode: SettingsWindowSizeMode { didSet { save(settingsWindowSizeMode.rawValue, Keys.settingsWindowSizeMode) } }
    @Published var showDetailedDescriptions: Bool { didSet { save(showDetailedDescriptions, Keys.showDetailedDescriptions) } }

    // v0.5.0 resource/profile layer. Resource modes change unnecessary work and
    // readiness, never the accuracy of the core total network measurement.
    @Published var resourceMode: ResourceMode { didSet { save(resourceMode.rawValue, Keys.resourceMode) } }
    @Published var austerityKeepTotalHistory: Bool { didSet { save(austerityKeepTotalHistory, Keys.austerityKeepTotalHistory) } }
    @Published var expertFeaturesEnabled: Bool { didSet { save(expertFeaturesEnabled, Keys.expertFeaturesEnabled) } }
    @Published var profiles: [NeManeemProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Keys.profiles) }
        }
    }

    @Published var advancedMenuBarExpanded: Bool
    @Published var menuFontFamily: String { didSet { save(menuFontFamily, Keys.menuFontFamily) } }
    @Published var menuFontSize: Double { didSet { save(menuFontSize, Keys.menuFontSize) } }
    @Published var valueAreaWidth: Double { didSet { save(valueAreaWidth, Keys.valueAreaWidth) } }
    @Published var iconAreaWidth: Double { didSet { save(iconAreaWidth, Keys.iconAreaWidth) } }
    @Published var metricGap: Double { didSet { save(metricGap, Keys.metricGap) } }
    @Published var rowSpacing: Double { didSet { save(rowSpacing, Keys.rowSpacing) } }

    @Published var popoverScale: PopoverScale { didSet { save(popoverScale.rawValue, Keys.popoverScale) } }
    @Published var popoverUnitMode: SpeedUnitMode { didSet { save(popoverUnitMode.rawValue, Keys.popoverUnitMode) } }
    @Published var popoverProcessDisplay: ProcessDisplayMode { didSet { save(popoverProcessDisplay.rawValue, Keys.popoverProcessDisplay) } }
    @Published var popoverDirectionDisplay: TransferDirectionDisplay { didSet { save(popoverDirectionDisplay.rawValue, Keys.popoverDirectionDisplay) } }
    @Published var popoverInactivePolicy: InactiveAppPolicy { didSet { save(popoverInactivePolicy.rawValue, Keys.popoverInactivePolicy) } }
    @Published var popoverHideInactiveApps: Bool { didSet { save(popoverHideInactiveApps, Keys.popoverHideInactiveApps) } }
    @Published var popoverInactiveHideDelaySeconds: Double { didSet { save(Self.normalizeInactiveHideDelay(popoverInactiveHideDelaySeconds), Keys.popoverInactiveHideDelaySeconds) } }
    @Published var popoverExitMotion: Bool { didSet { save(popoverExitMotion, Keys.popoverExitMotion) } }
    @Published var popoverSortMode: TrafficSortMode { didSet { save(popoverSortMode.rawValue, Keys.popoverSortMode) } }
    @Published var popoverShowControls: Bool { didSet { save(popoverShowControls, Keys.popoverShowControls) } }
    @Published var popoverShowTotalSpeed: Bool { didSet { save(popoverShowTotalSpeed, Keys.popoverShowTotalSpeed) } }
    @Published var popoverManualOrder: [String] { didSet { save(popoverManualOrder, Keys.popoverManualOrder) } }
    @Published var popoverHiddenProcessIDs: [String] { didSet { save(popoverHiddenProcessIDs, Keys.popoverHiddenProcessIDs) } }
    @Published var popoverGroupSystemProcesses: Bool { didSet { save(popoverGroupSystemProcesses, Keys.popoverGroupSystemProcesses) } }
    @Published var popoverVisibilityMode: AppVisibilityMode { didSet { save(popoverVisibilityMode.rawValue, Keys.popoverVisibilityMode) } }
    @Published var popoverSelectedProcessIDs: [String] { didSet { save(popoverSelectedProcessIDs, Keys.popoverSelectedProcessIDs) } }
    @Published var popoverGroupAppleApps: Bool { didSet { save(popoverGroupAppleApps, Keys.popoverGroupAppleApps) } }
    @Published var popoverHideLowActivityApps: Bool { didSet { save(popoverHideLowActivityApps, Keys.popoverHideLowActivityApps) } }
    // Legacy rate threshold is kept only for preference migration compatibility.
    @Published var popoverLowActivityThresholdKBps: Double { didSet { save(Self.normalizeLowActivityThreshold(popoverLowActivityThresholdKBps), Keys.popoverLowActivityThresholdKBps) } }
    @Published var popoverLowActivityThresholdUnit: LowActivityRateUnit { didSet { save(popoverLowActivityThresholdUnit.rawValue, Keys.popoverLowActivityThresholdUnit) } }
    @Published var popoverLowActivityDurationValue: Double { didSet { save(Self.normalizeLowActivityDuration(popoverLowActivityDurationValue), Keys.popoverLowActivityDurationValue) } }
    @Published var popoverLowActivityDurationUnit: LowActivityDurationUnit { didSet { save(popoverLowActivityDurationUnit.rawValue, Keys.popoverLowActivityDurationUnit) } }
    @Published var popoverLowActivityDataValue: Double { didSet { save(Self.normalizeLowActivityData(popoverLowActivityDataValue), Keys.popoverLowActivityDataValue) } }
    @Published var popoverLowActivityDataUnit: LowActivityDataUnit { didSet { save(popoverLowActivityDataUnit.rawValue, Keys.popoverLowActivityDataUnit) } }
    @Published var popoverGroupUnselectedApps: Bool { didSet { save(popoverGroupUnselectedApps, Keys.popoverGroupUnselectedApps) } }
    @Published var advancedProcessControlsEnabled: Bool { didSet { save(advancedProcessControlsEnabled, Keys.advancedProcessControlsEnabled) } }
    @Published var hiddenDetailProcessIDs: [String] { didSet { save(hiddenDetailProcessIDs, Keys.hiddenDetailProcessIDs) } }
    @Published var manualParentAppMappings: [String: String] { didSet { save(manualParentAppMappings, Keys.manualParentAppMappings) } }
    @Published var popoverColumns: [StatusColumn] { didSet { save(popoverColumns.map(\.rawValue), Keys.popoverColumns) } }
    @Published var trafficOrderPresets: [TrafficOrderPreset] { didSet { savePresets() } }

    @Published var monitorUsePopoverSettings: Bool { didSet { save(monitorUsePopoverSettings, Keys.monitorUsePopoverSettings) } }
    @Published var monitorScale: PopoverScale { didSet { save(monitorScale.rawValue, Keys.monitorScale) } }
    @Published var monitorUnitMode: SpeedUnitMode { didSet { save(monitorUnitMode.rawValue, Keys.monitorUnitMode) } }
    @Published var monitorProcessDisplay: ProcessDisplayMode { didSet { save(monitorProcessDisplay.rawValue, Keys.monitorProcessDisplay) } }
    @Published var monitorDirectionDisplay: TransferDirectionDisplay { didSet { save(monitorDirectionDisplay.rawValue, Keys.monitorDirectionDisplay) } }
    @Published var monitorInactivePolicy: InactiveAppPolicy { didSet { save(monitorInactivePolicy.rawValue, Keys.monitorInactivePolicy) } }
    @Published var monitorHideInactiveApps: Bool { didSet { save(monitorHideInactiveApps, Keys.monitorHideInactiveApps) } }
    @Published var monitorInactiveHideDelaySeconds: Double { didSet { save(Self.normalizeInactiveHideDelay(monitorInactiveHideDelaySeconds), Keys.monitorInactiveHideDelaySeconds) } }
    @Published var monitorExitMotion: Bool { didSet { save(monitorExitMotion, Keys.monitorExitMotion) } }
    @Published var monitorSortMode: TrafficSortMode { didSet { save(monitorSortMode.rawValue, Keys.monitorSortMode) } }
    @Published var monitorManualOrder: [String] { didSet { save(monitorManualOrder, Keys.monitorManualOrder) } }
    @Published var monitorHiddenProcessIDs: [String] { didSet { save(monitorHiddenProcessIDs, Keys.monitorHiddenProcessIDs) } }
    @Published var monitorGroupSystemProcesses: Bool { didSet { save(monitorGroupSystemProcesses, Keys.monitorGroupSystemProcesses) } }
    @Published var monitorVisibilityMode: AppVisibilityMode { didSet { save(monitorVisibilityMode.rawValue, Keys.monitorVisibilityMode) } }
    @Published var monitorSelectedProcessIDs: [String] { didSet { save(monitorSelectedProcessIDs, Keys.monitorSelectedProcessIDs) } }
    @Published var monitorGroupAppleApps: Bool { didSet { save(monitorGroupAppleApps, Keys.monitorGroupAppleApps) } }
    @Published var monitorHideLowActivityApps: Bool { didSet { save(monitorHideLowActivityApps, Keys.monitorHideLowActivityApps) } }
    // Legacy rate threshold is kept only for preference migration compatibility.
    @Published var monitorLowActivityThresholdKBps: Double { didSet { save(Self.normalizeLowActivityThreshold(monitorLowActivityThresholdKBps), Keys.monitorLowActivityThresholdKBps) } }
    @Published var monitorLowActivityThresholdUnit: LowActivityRateUnit { didSet { save(monitorLowActivityThresholdUnit.rawValue, Keys.monitorLowActivityThresholdUnit) } }
    @Published var monitorLowActivityDurationValue: Double { didSet { save(Self.normalizeLowActivityDuration(monitorLowActivityDurationValue), Keys.monitorLowActivityDurationValue) } }
    @Published var monitorLowActivityDurationUnit: LowActivityDurationUnit { didSet { save(monitorLowActivityDurationUnit.rawValue, Keys.monitorLowActivityDurationUnit) } }
    @Published var monitorLowActivityDataValue: Double { didSet { save(Self.normalizeLowActivityData(monitorLowActivityDataValue), Keys.monitorLowActivityDataValue) } }
    @Published var monitorLowActivityDataUnit: LowActivityDataUnit { didSet { save(monitorLowActivityDataUnit.rawValue, Keys.monitorLowActivityDataUnit) } }
    @Published var monitorGroupUnselectedApps: Bool { didSet { save(monitorGroupUnselectedApps, Keys.monitorGroupUnselectedApps) } }
    @Published var monitorColumns: [StatusColumn] { didSet { save(monitorColumns.map(\.rawValue), Keys.monitorColumns) } }

    @Published var recordingMode: RecordingMode { didSet { save(recordingMode.rawValue, Keys.recordingMode) } }
    @Published var processDetailRecordingEnabled: Bool { didSet { save(processDetailRecordingEnabled, Keys.processDetailRecordingEnabled) } }
    @Published var historyRetentionDays: Int { didSet { save(max(0, historyRetentionDays), Keys.retentionDays) } }

    @Published var separateLocalTraffic: Bool { didSet { save(separateLocalTraffic, Keys.separateLocalTraffic) } }
    /// Optional compatibility mapping. Default OFF because public Network Extension
    /// metadata cannot prove that every WebKit Networking flow belongs to Safari.
    @Published var safariNetworkServiceGroupingEnabled: Bool {
        didSet { save(safariNetworkServiceGroupingEnabled, AppConstants.safariNetworkServiceGroupingDefaultsKey) }
    }
    @Published var localTrafficStatisticsMode: LocalTrafficStatisticsMode { didSet { save(localTrafficStatisticsMode.rawValue, Keys.localTrafficStatisticsMode) } }
    @Published var dataLimitTrafficScope: DataLimitTrafficScope { didSet { save(dataLimitTrafficScope.rawValue, Keys.dataLimitTrafficScope) } }
    @Published var dataLimitNetworkTargetMode: DataLimitNetworkTargetMode { didSet { save(dataLimitNetworkTargetMode.rawValue, Keys.dataLimitNetworkTargetMode) } }
    @Published var dataLimitNetworkIdentifier: String { didSet { save(dataLimitNetworkIdentifier, Keys.dataLimitNetworkIdentifier) } }
    @Published var dataLimitNetworkDisplayName: String { didSet { save(dataLimitNetworkDisplayName, Keys.dataLimitNetworkDisplayName) } }
    @Published var menuBarTrafficScope: MenuBarTrafficScope { didSet { save(menuBarTrafficScope.rawValue, Keys.menuBarTrafficScope) } }

    /// A disabled local/internet classifier must not leave an invisible Internet-only
    /// choice active behind a disabled control. Preserve the user's stored choice so
    /// it returns when classification is enabled again, but use all traffic while the
    /// classifier itself is off.
    var effectiveMenuBarTrafficScope: MenuBarTrafficScope {
        separateLocalTraffic ? menuBarTrafficScope : .allTraffic
    }

    var effectiveDataLimitTrafficScope: DataLimitTrafficScope {
        separateLocalTraffic ? dataLimitTrafficScope : .allTraffic
    }

    @Published var dataLimitEnabled: Bool { didSet { save(dataLimitEnabled, Keys.dataLimitEnabled) } }
    @Published var dataLimitValue: Double { didSet { save(max(0, dataLimitValue), Keys.dataLimitValue) } }
    @Published var dataLimitUnit: DataLimitUnit { didSet { save(dataLimitUnit.rawValue, Keys.dataLimitUnit) } }
    @Published var dataLimitRenewalDay: Int { didSet { save(dataLimitRenewalDay, Keys.dataLimitRenewalDay) } }
    @Published var dataRenewalMode: DataRenewalMode { didSet { save(dataRenewalMode.rawValue, Keys.dataRenewalMode) } }
    @Published var dataLimitStartDate: Date { didSet { defaults.set(dataLimitStartDate, forKey: Keys.dataLimitStartDate) } }
    @Published var showDataLimitInPopover: Bool { didSet { save(showDataLimitInPopover, Keys.showDataLimitInPopover) } }
    @Published var showDataLimitInMonitor: Bool { didSet { save(showDataLimitInMonitor, Keys.showDataLimitInMonitor) } }
    @Published var dataLimitDisplayMode: DataLimitDisplayMode { didSet { save(dataLimitDisplayMode.rawValue, Keys.dataLimitDisplayMode) } }
    @Published var dataLimitWarningEnabled: Bool { didSet { save(dataLimitWarningEnabled, Keys.dataLimitWarningEnabled) } }
    @Published var dataLimitWarningLightLinked: Bool { didSet { save(dataLimitWarningLightLinked, Keys.dataLimitWarningLightLinked) } }
    @Published var dataLimitWarningLightYellowRuleID: String { didSet { save(dataLimitWarningLightYellowRuleID, Keys.dataLimitWarningLightYellowRuleID) } }
    @Published var dataLimitWarningLightOrangeRuleID: String { didSet { save(dataLimitWarningLightOrangeRuleID, Keys.dataLimitWarningLightOrangeRuleID) } }
    @Published var dataLimitWarningLightRedRuleID: String { didSet { save(dataLimitWarningLightRedRuleID, Keys.dataLimitWarningLightRedRuleID) } }
    @Published var dataLimitWarningMode: DataLimitWarningMode { didSet { save(dataLimitWarningMode.rawValue, Keys.dataLimitWarningMode) } }
    @Published var dataLimitWarningPercentage: Double { didSet { save(min(99, max(1, dataLimitWarningPercentage)), Keys.dataLimitWarningPercentage) } }
    @Published var dataLimitWarningRemainingValue: Double { didSet { save(max(0, dataLimitWarningRemainingValue), Keys.dataLimitWarningRemainingValue) } }
    @Published var dataLimitWarningRemainingUnit: DataLimitUnit { didSet { save(dataLimitWarningRemainingUnit.rawValue, Keys.dataLimitWarningRemainingUnit) } }

    @Published var dataLimitPeriodMode: DataLimitPeriodMode { didSet { save(dataLimitPeriodMode.rawValue, Keys.dataLimitPeriodMode) } }
    @Published var dataLimitPeriodValue: Int { didSet { save(max(1, dataLimitPeriodValue), Keys.dataLimitPeriodValue) } }
    @Published var dataLimitPeriodUnit: DataLimitPeriodUnit { didSet { save(dataLimitPeriodUnit.rawValue, Keys.dataLimitPeriodUnit) } }
    @Published var dataLimitSelectedEndMonth: Int { didSet { save(min(12, max(1, dataLimitSelectedEndMonth)), Keys.dataLimitSelectedEndMonth) } }
    @Published var dataLimitEndDate: Date { didSet { defaults.set(dataLimitEndDate, forKey: Keys.dataLimitEndDate) } }
    @Published var dataLimitEndBehavior: DataLimitEndBehavior { didSet { save(dataLimitEndBehavior.rawValue, Keys.dataLimitEndBehavior) } }
    @Published var dataLimitMonthlyStartDay: Int { didSet { save(min(31, max(1, dataLimitMonthlyStartDay)), Keys.dataLimitMonthlyStartDay) } }
    @Published var dataLimitReachedAction: DataLimitReachedAction { didSet { save(dataLimitReachedAction.rawValue, Keys.dataLimitReachedAction) } }
    // The user-facing "Starting Remaining Limit" is fixed only when the user
    // presses Apply. It is deliberately independent from live recorded traffic.
    @Published var dataLimitStartingRemainingBytes: Double { didSet { save(max(0, dataLimitStartingRemainingBytes), Keys.dataLimitStartingRemainingBytes) } }
    @Published var dataLimitStartingRemainingApplied: Bool { didSet { save(dataLimitStartingRemainingApplied, Keys.dataLimitStartingRemainingApplied) } }
    @Published var dataLimitWarningRules: [DataLimitWarningRule] { didSet { saveWarningRules() } }
    @Published var dataLimitWarningRepeatMinutes: Int { didSet { save(max(0, dataLimitWarningRepeatMinutes), Keys.dataLimitWarningRepeatMinutes) } }

    @Published var sessionEnabled: Bool { didSet { save(sessionEnabled, Keys.sessionEnabled) } }
    @Published var showSessionInPopover: Bool { didSet { save(showSessionInPopover, Keys.showSessionInPopover) } }
    @Published var sessionStartDate: Date { didSet { defaults.set(sessionStartDate, forKey: Keys.sessionStartDate) } }
    @Published var sessionStartMode: SessionStartMode { didSet { save(sessionStartMode.rawValue, Keys.sessionStartMode) } }
    @Published var scheduledSessionStartDate: Date { didSet { defaults.set(scheduledSessionStartDate, forKey: Keys.scheduledSessionStartDate) } }
    @Published var scheduledSessionEndMode: SessionScheduleEndMode { didSet { save(scheduledSessionEndMode.rawValue, Keys.scheduledSessionEndMode) } }
    @Published var scheduledSessionEndDate: Date { didSet { defaults.set(scheduledSessionEndDate, forKey: Keys.scheduledSessionEndDate) } }
    @Published var scheduledSessionDurationMinutes: Int { didSet { save(max(1, scheduledSessionDurationMinutes), Keys.scheduledSessionDurationMinutes) } }
    @Published var sessionFollowsDataRenewal: Bool { didSet { save(sessionFollowsDataRenewal, Keys.sessionFollowsDataRenewal) } }

    @Published var alwaysOnTopMonitor: Bool { didSet { save(alwaysOnTopMonitor, Keys.alwaysOnTopMonitor) } }
    @Published var monitorShowTotalSpeed: Bool { didSet { save(monitorShowTotalSpeed, Keys.monitorShowTotalSpeed) } }
    @Published var monitorShowNetwork: Bool { didSet { save(monitorShowNetwork, Keys.monitorShowNetwork) } }
    @Published var monitorShowData: Bool { didSet { save(monitorShowData, Keys.monitorShowData) } }
    @Published var monitorShowControls: Bool { didSet { save(monitorShowControls, Keys.monitorShowControls) } }

    init() {
        showDownload = defaults.object(forKey: Keys.showDownload) as? Bool ?? true
        showUpload = defaults.object(forKey: Keys.showUpload) as? Bool ?? true
        metricOrder = MenuMetricOrder(rawValue: defaults.string(forKey: Keys.metricOrder) ?? "") ?? .downloadFirst
        menuDisplayStyle = LegacyMenuDisplayStyle(rawValue: defaults.string(forKey: Keys.menuDisplayStyle) ?? "") ?? .twoLineCompact
        showIcons = defaults.object(forKey: Keys.showIcons) as? Bool ?? false
        let loadedMenuBarTop = Self.loadMenuBarElements(defaults.stringArray(forKey: Keys.menuBarTopElements), fallback: MenuBarElement.defaultTop)
        let loadedMenuBarBottom = Self.loadMenuBarElements(defaults.stringArray(forKey: Keys.menuBarBottomElements), fallback: MenuBarElement.defaultBottom)
        let normalizedMenuBarLayout = Self.normalizeMenuBarLayout(top: loadedMenuBarTop, bottom: loadedMenuBarBottom)
        menuBarTopElements = normalizedMenuBarLayout.top
        menuBarBottomElements = normalizedMenuBarLayout.bottom
        unitMode = SpeedUnitMode(rawValue: defaults.string(forKey: Keys.unitMode) ?? "") ?? .compactBytes
        let refreshDefaultsVersion = defaults.integer(forKey: Keys.refreshDefaultsVersion)
        let storedMenuRefresh = defaults.object(forKey: Keys.refreshInterval) as? Double
        let storedPopoverRefresh = defaults.object(forKey: Keys.popoverRefreshInterval) as? Double
        let storedMonitorRefresh = defaults.object(forKey: Keys.monitorRefreshInterval) as? Double

        // 0.3.9 changes the everyday default from 1 s to 3 s. Migrate an old
        // untouched 1 s default once; the final presets are 0.25 / 3 / 10 / Custom.
        if refreshDefaultsVersion < 1 {
            refreshIntervalSeconds = Self.normalizeInterval((storedMenuRefresh == nil || abs(storedMenuRefresh! - 1.0) < 0.001) ? 3.0 : storedMenuRefresh!)
            popoverRefreshIntervalSeconds = Self.normalizeInterval((storedPopoverRefresh == nil || abs(storedPopoverRefresh! - 1.0) < 0.001) ? 3.0 : storedPopoverRefresh!)
            monitorRefreshIntervalSeconds = Self.normalizeInterval((storedMonitorRefresh == nil || abs(storedMonitorRefresh! - 1.0) < 0.001) ? 3.0 : storedMonitorRefresh!)
            defaults.set(1, forKey: Keys.refreshDefaultsVersion)
        } else {
            refreshIntervalSeconds = Self.normalizeInterval(storedMenuRefresh ?? 3.0)
            popoverRefreshIntervalSeconds = Self.normalizeInterval(storedPopoverRefresh ?? 3.0)
            monitorRefreshIntervalSeconds = Self.normalizeInterval(storedMonitorRefresh ?? 3.0)
        }
        // Status-window default: follow the menu bar unless the user explicitly
        // chooses a separate Popover sampling interval.
        popoverUseMenuBarRefresh = defaults.object(forKey: Keys.popoverUseMenuBarRefresh) as? Bool ?? true
        popoverClosedDataRetentionSeconds = Self.normalizeClosedDataRetention(defaults.object(forKey: Keys.popoverClosedDataRetention) as? Double ?? 5.0)
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        accentMode = AppAccentMode(rawValue: defaults.string(forKey: Keys.accentMode) ?? "") ?? .system
        customAccentHex = defaults.string(forKey: Keys.customAccentHex) ?? NeManeemTheme.defaultCustomAccentHex
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        settingsWindowSizeMode = SettingsWindowSizeMode(rawValue: defaults.string(forKey: Keys.settingsWindowSizeMode) ?? "") ?? .widthFixed
        showDetailedDescriptions = defaults.object(forKey: Keys.showDetailedDescriptions) as? Bool ?? false
        resourceMode = ResourceMode(rawValue: defaults.string(forKey: Keys.resourceMode) ?? "") ?? .balanced
        austerityKeepTotalHistory = defaults.object(forKey: Keys.austerityKeepTotalHistory) as? Bool ?? false
        expertFeaturesEnabled = defaults.object(forKey: Keys.expertFeaturesEnabled) as? Bool ?? false
        if let profileData = defaults.data(forKey: Keys.profiles),
           let decodedProfiles = try? JSONDecoder().decode([NeManeemProfile].self, from: profileData) {
            profiles = decodedProfiles
        } else {
            profiles = []
        }

        advancedMenuBarExpanded = false
        menuFontFamily = defaults.string(forKey: Keys.menuFontFamily) ?? ""
        menuFontSize = defaults.object(forKey: Keys.menuFontSize) as? Double ?? Self.defaultMenuFontSize
        let sizingVersion = defaults.integer(forKey: Keys.menuSizingVersion)
        let storedValueWidth = defaults.object(forKey: Keys.valueAreaWidth) as? Double
        let storedIconWidth = defaults.object(forKey: Keys.iconAreaWidth) as? Double
        if sizingVersion < 2 {
            valueAreaWidth = (storedValueWidth == nil || storedValueWidth == 34.0) ? 28.0 : storedValueWidth!
            iconAreaWidth = (storedIconWidth == nil || storedIconWidth == 10.0) ? 8.0 : storedIconWidth!
            defaults.set(2, forKey: Keys.menuSizingVersion)
        } else {
            valueAreaWidth = storedValueWidth ?? 28.0
            iconAreaWidth = storedIconWidth ?? 8.0
        }
        metricGap = defaults.object(forKey: Keys.metricGap) as? Double ?? 5.0
        rowSpacing = defaults.object(forKey: Keys.rowSpacing) as? Double ?? 0.5

        popoverScale = PopoverScale(rawValue: defaults.string(forKey: Keys.popoverScale) ?? "") ?? .standard
        popoverUnitMode = SpeedUnitMode(rawValue: defaults.string(forKey: Keys.popoverUnitMode) ?? "") ?? .bytesPerSecond
        popoverProcessDisplay = ProcessDisplayMode(rawValue: defaults.string(forKey: Keys.popoverProcessDisplay) ?? "") ?? .iconAndName
        popoverDirectionDisplay = TransferDirectionDisplay(rawValue: defaults.string(forKey: Keys.popoverDirectionDisplay) ?? "") ?? .words
        popoverInactivePolicy = InactiveAppPolicy(rawValue: defaults.string(forKey: Keys.popoverInactivePolicy) ?? "") ?? .seconds3
        // 0.4.0 Build 44 separates value sampling from row disappearance. Keep the
        // calmer behaviour as the new default: inactive apps stay visible unless
        // the user explicitly enables automatic hiding.
        popoverHideInactiveApps = defaults.object(forKey: Keys.popoverHideInactiveApps) as? Bool ?? false
        popoverInactiveHideDelaySeconds = Self.normalizeInactiveHideDelay(defaults.object(forKey: Keys.popoverInactiveHideDelaySeconds) as? Double ?? 10.0)
        popoverExitMotion = defaults.object(forKey: Keys.popoverExitMotion) as? Bool ?? false
        popoverSortMode = TrafficSortMode(rawValue: defaults.string(forKey: Keys.popoverSortMode) ?? "") ?? .currentUsage
        popoverShowControls = defaults.object(forKey: Keys.popoverShowControls) as? Bool ?? false
        // Presentation-only defaults may start ON when they make the ordinary UI
        // easier to understand without recording more data, requesting permission,
        // hiding user apps, or changing network behavior. Stored user choices still
        // win, so an explicit OFF is never migrated back to ON.
        popoverShowTotalSpeed = defaults.object(forKey: Keys.popoverShowTotalSpeed) as? Bool ?? true
        popoverManualOrder = defaults.stringArray(forKey: Keys.popoverManualOrder) ?? []
        popoverHiddenProcessIDs = defaults.stringArray(forKey: Keys.popoverHiddenProcessIDs) ?? []
        popoverGroupSystemProcesses = defaults.object(forKey: Keys.popoverGroupSystemProcesses) as? Bool ?? true
        popoverVisibilityMode = AppVisibilityMode(rawValue: defaults.string(forKey: Keys.popoverVisibilityMode) ?? "") ?? .allApps
        popoverSelectedProcessIDs = defaults.stringArray(forKey: Keys.popoverSelectedProcessIDs) ?? []
        // Preserve the existing Build 26 display by default. New grouping/filtering
        // features are opt-in unless the user explicitly chooses Selected Apps Only.
        popoverGroupAppleApps = defaults.object(forKey: Keys.popoverGroupAppleApps) as? Bool ?? false
        popoverHideLowActivityApps = defaults.object(forKey: Keys.popoverHideLowActivityApps) as? Bool ?? false
        popoverLowActivityThresholdKBps = Self.normalizeLowActivityThreshold(defaults.object(forKey: Keys.popoverLowActivityThresholdKBps) as? Double ?? 1.0)
        popoverLowActivityThresholdUnit = LowActivityRateUnit(rawValue: defaults.string(forKey: Keys.popoverLowActivityThresholdUnit) ?? "") ?? .kilobytesPerSecond
        if defaults.object(forKey: Keys.popoverLowActivityDurationValue) == nil {
            popoverLowActivityDurationValue = 5
            popoverLowActivityDurationUnit = .minutes
            popoverLowActivityDataValue = 100
            popoverLowActivityDataUnit = .kilobytes
        } else {
            popoverLowActivityDurationValue = Self.normalizeLowActivityDuration(defaults.object(forKey: Keys.popoverLowActivityDurationValue) as? Double ?? 5)
            popoverLowActivityDurationUnit = LowActivityDurationUnit(rawValue: defaults.string(forKey: Keys.popoverLowActivityDurationUnit) ?? "") ?? .minutes
            popoverLowActivityDataValue = Self.normalizeLowActivityData(defaults.object(forKey: Keys.popoverLowActivityDataValue) as? Double ?? 100)
            popoverLowActivityDataUnit = LowActivityDataUnit(rawValue: defaults.string(forKey: Keys.popoverLowActivityDataUnit) ?? "") ?? .kilobytes
        }
        popoverGroupUnselectedApps = defaults.object(forKey: Keys.popoverGroupUnselectedApps) as? Bool ?? false
        advancedProcessControlsEnabled = defaults.object(forKey: Keys.advancedProcessControlsEnabled) as? Bool ?? false
        hiddenDetailProcessIDs = defaults.stringArray(forKey: Keys.hiddenDetailProcessIDs) ?? []
        manualParentAppMappings = defaults.dictionary(forKey: Keys.manualParentAppMappings) as? [String: String] ?? [:]
        popoverColumns = Self.loadColumns(defaults.stringArray(forKey: Keys.popoverColumns))
        if let data = defaults.data(forKey: Keys.trafficOrderPresets),
           let decoded = try? JSONDecoder().decode([TrafficOrderPreset].self, from: data) {
            trafficOrderPresets = decoded
        } else {
            trafficOrderPresets = []
        }

        monitorUsePopoverSettings = defaults.object(forKey: Keys.monitorUsePopoverSettings) as? Bool ?? true
        // Independent monitor settings previously always used their own interval.
        // Keep that meaning for existing installs until the user selects the new
        // "same as menu bar" choice explicitly.
        monitorUseMenuBarRefresh = defaults.object(forKey: Keys.monitorUseMenuBarRefresh) as? Bool ?? false
        monitorScale = PopoverScale(rawValue: defaults.string(forKey: Keys.monitorScale) ?? "") ?? .standard
        monitorUnitMode = SpeedUnitMode(rawValue: defaults.string(forKey: Keys.monitorUnitMode) ?? "") ?? .bytesPerSecond
        monitorProcessDisplay = ProcessDisplayMode(rawValue: defaults.string(forKey: Keys.monitorProcessDisplay) ?? "") ?? .iconAndName
        monitorDirectionDisplay = TransferDirectionDisplay(rawValue: defaults.string(forKey: Keys.monitorDirectionDisplay) ?? "") ?? .words
        monitorInactivePolicy = InactiveAppPolicy(rawValue: defaults.string(forKey: Keys.monitorInactivePolicy) ?? "") ?? .seconds3
        monitorHideInactiveApps = defaults.object(forKey: Keys.monitorHideInactiveApps) as? Bool ?? false
        monitorInactiveHideDelaySeconds = Self.normalizeInactiveHideDelay(defaults.object(forKey: Keys.monitorInactiveHideDelaySeconds) as? Double ?? 10.0)
        monitorExitMotion = defaults.object(forKey: Keys.monitorExitMotion) as? Bool ?? false
        monitorSortMode = TrafficSortMode(rawValue: defaults.string(forKey: Keys.monitorSortMode) ?? "") ?? .currentUsage
        monitorManualOrder = defaults.stringArray(forKey: Keys.monitorManualOrder) ?? []
        monitorHiddenProcessIDs = defaults.stringArray(forKey: Keys.monitorHiddenProcessIDs) ?? []
        monitorGroupSystemProcesses = defaults.object(forKey: Keys.monitorGroupSystemProcesses) as? Bool ?? true
        monitorVisibilityMode = AppVisibilityMode(rawValue: defaults.string(forKey: Keys.monitorVisibilityMode) ?? "") ?? .allApps
        monitorSelectedProcessIDs = defaults.stringArray(forKey: Keys.monitorSelectedProcessIDs) ?? []
        monitorGroupAppleApps = defaults.object(forKey: Keys.monitorGroupAppleApps) as? Bool ?? false
        monitorHideLowActivityApps = defaults.object(forKey: Keys.monitorHideLowActivityApps) as? Bool ?? false
        monitorLowActivityThresholdKBps = Self.normalizeLowActivityThreshold(defaults.object(forKey: Keys.monitorLowActivityThresholdKBps) as? Double ?? 1.0)
        monitorLowActivityThresholdUnit = LowActivityRateUnit(rawValue: defaults.string(forKey: Keys.monitorLowActivityThresholdUnit) ?? "") ?? .kilobytesPerSecond
        if defaults.object(forKey: Keys.monitorLowActivityDurationValue) == nil {
            monitorLowActivityDurationValue = 5
            monitorLowActivityDurationUnit = .minutes
            monitorLowActivityDataValue = 100
            monitorLowActivityDataUnit = .kilobytes
        } else {
            monitorLowActivityDurationValue = Self.normalizeLowActivityDuration(defaults.object(forKey: Keys.monitorLowActivityDurationValue) as? Double ?? 5)
            monitorLowActivityDurationUnit = LowActivityDurationUnit(rawValue: defaults.string(forKey: Keys.monitorLowActivityDurationUnit) ?? "") ?? .minutes
            monitorLowActivityDataValue = Self.normalizeLowActivityData(defaults.object(forKey: Keys.monitorLowActivityDataValue) as? Double ?? 100)
            monitorLowActivityDataUnit = LowActivityDataUnit(rawValue: defaults.string(forKey: Keys.monitorLowActivityDataUnit) ?? "") ?? .kilobytes
        }
        monitorGroupUnselectedApps = defaults.object(forKey: Keys.monitorGroupUnselectedApps) as? Bool ?? false
        monitorColumns = Self.loadColumns(defaults.stringArray(forKey: Keys.monitorColumns))

        let storedRecordingMode = RecordingMode(rawValue: defaults.string(forKey: Keys.recordingMode) ?? "") ?? .off
        // v0.5.22 removes the user-facing recording-method choice. When recording
        // is enabled, keep both overall and per-app usage so exported data remains
        // useful without asking users to predict future analysis needs.
        recordingMode = storedRecordingMode == .off ? .off : .perApp
        processDetailRecordingEnabled = defaults.object(forKey: Keys.processDetailRecordingEnabled) as? Bool ?? false
        historyRetentionDays = max(0, defaults.object(forKey: Keys.retentionDays) as? Int ?? 30)

        separateLocalTraffic = defaults.object(forKey: Keys.separateLocalTraffic) as? Bool ?? false
        safariNetworkServiceGroupingEnabled = defaults.object(forKey: AppConstants.safariNetworkServiceGroupingDefaultsKey) as? Bool ?? true
        localTrafficStatisticsMode = LocalTrafficStatisticsMode(rawValue: defaults.string(forKey: Keys.localTrafficStatisticsMode) ?? "") ?? .separate
        dataLimitTrafficScope = DataLimitTrafficScope(rawValue: defaults.string(forKey: Keys.dataLimitTrafficScope) ?? "") ?? .internetOnly
        dataLimitNetworkTargetMode = DataLimitNetworkTargetMode(rawValue: defaults.string(forKey: Keys.dataLimitNetworkTargetMode) ?? "") ?? .allNetworks
        dataLimitNetworkIdentifier = defaults.string(forKey: Keys.dataLimitNetworkIdentifier) ?? ""
        dataLimitNetworkDisplayName = defaults.string(forKey: Keys.dataLimitNetworkDisplayName) ?? ""
        menuBarTrafficScope = MenuBarTrafficScope(rawValue: defaults.string(forKey: Keys.menuBarTrafficScope) ?? "") ?? .allTraffic

        dataLimitEnabled = defaults.object(forKey: Keys.dataLimitEnabled) as? Bool ?? false
        if let storedValue = defaults.object(forKey: Keys.dataLimitValue) as? Double {
            dataLimitValue = max(0, storedValue)
            dataLimitUnit = DataLimitUnit(rawValue: defaults.string(forKey: Keys.dataLimitUnit) ?? "") ?? .gigabytes
        } else {
            // Migration from the 0.2.7-and-earlier GB-only setting.
            dataLimitValue = max(0, defaults.object(forKey: Keys.legacyDataLimitGB) as? Double ?? 10.0)
            dataLimitUnit = .gigabytes
        }
        // Resolve all data-limit migration inputs as local values first. Swift does
        // not allow reading another instance property through `self` until every
        // stored property has been initialized, even when that property was assigned
        // a few lines earlier in this initializer.
        let loadedRenewalDay = min(31, max(1, defaults.object(forKey: Keys.dataLimitRenewalDay) as? Int ?? 1))
        let loadedRenewalMode = DataRenewalMode(rawValue: defaults.string(forKey: Keys.dataRenewalMode) ?? "") ?? .monthly
        let loadedLimitStartDate = defaults.object(forKey: Keys.dataLimitStartDate) as? Date ?? Date()
        let loadedWarningMode = DataLimitWarningMode(rawValue: defaults.string(forKey: Keys.dataLimitWarningMode) ?? "") ?? .percentage
        let loadedWarningPercentage = min(99, max(1, defaults.object(forKey: Keys.dataLimitWarningPercentage) as? Double ?? 80))
        let loadedWarningRemainingValue = max(0, defaults.object(forKey: Keys.dataLimitWarningRemainingValue) as? Double ?? 1)
        let loadedWarningRemainingUnit = DataLimitUnit(rawValue: defaults.string(forKey: Keys.dataLimitWarningRemainingUnit) ?? "") ?? .gigabytes
        let loadedWarningLightYellowRuleID = defaults.string(forKey: Keys.dataLimitWarningLightYellowRuleID) ?? ""
        let hasExistingDataLimitConfiguration =
            defaults.object(forKey: Keys.dataLimitEnabled) != nil ||
            defaults.object(forKey: Keys.dataLimitValue) != nil ||
            defaults.object(forKey: Keys.legacyDataLimitGB) != nil ||
            defaults.object(forKey: Keys.dataLimitWarningEnabled) != nil ||
            defaults.object(forKey: Keys.dataLimitWarningRules) != nil ||
            defaults.object(forKey: Keys.dataLimitWarningLightLinked) != nil ||
            defaults.object(forKey: Keys.dataLimitWarningLightYellowRuleID) != nil ||
            defaults.object(forKey: Keys.dataLimitWarningLightRedRuleID) != nil
        let loadedWarningRules: [DataLimitWarningRule]
        if let data = defaults.data(forKey: Keys.dataLimitWarningRules),
           let decoded = try? JSONDecoder().decode([DataLimitWarningRule].self, from: data),
           !decoded.isEmpty {
            let limited = Array(decoded.prefix(Self.maximumDataLimitWarningRules))
            loadedWarningRules = limited
            if limited.count != decoded.count,
               let encoded = try? JSONEncoder().encode(limited) {
                // Build 116 establishes three warnings as the product maximum.
                // Older preview builds allowed more; keep the earliest ordered
                // milestones and discard only the now-invalid overflow entries.
                defaults.set(encoded, forKey: Keys.dataLimitWarningRules)
            }
        } else if !hasExistingDataLimitConfiguration {
            // A clean install starts with the three-stage light mapping's two
            // warning milestones. Existing installations keep their previous
            // saved/default warning shape instead of receiving a silent rule.
            loadedWarningRules = [
                DataLimitWarningRule(mode: .percentage, percentage: 80),
                DataLimitWarningRule(mode: .percentage, percentage: 90)
            ]
            if let encoded = try? JSONEncoder().encode(loadedWarningRules) {
                defaults.set(encoded, forKey: Keys.dataLimitWarningRules)
            }
        } else {
            loadedWarningRules = [DataLimitWarningRule(mode: loadedWarningMode,
                                                       percentage: loadedWarningPercentage,
                                                       remainingValue: loadedWarningRemainingValue,
                                                       remainingUnit: loadedWarningRemainingUnit)]
        }
        let storedWarningLightRedRuleID = defaults.string(forKey: Keys.dataLimitWarningLightRedRuleID) ?? ""
        let storedWarningLightOrangeRuleID = defaults.string(forKey: Keys.dataLimitWarningLightOrangeRuleID) ?? ""
        let loadedWarningLightRedRuleID: String
        if !storedWarningLightRedRuleID.isEmpty {
            loadedWarningLightRedRuleID = storedWarningLightRedRuleID
        } else if !hasExistingDataLimitConfiguration {
            loadedWarningLightRedRuleID = "__limit__"
        } else if let yellowIndex = loadedWarningRules.firstIndex(where: { $0.id.uuidString == loadedWarningLightYellowRuleID }),
                  loadedWarningRules.indices.contains(yellowIndex + 1) {
            loadedWarningLightRedRuleID = loadedWarningRules[yellowIndex + 1].id.uuidString
        } else {
            loadedWarningLightRedRuleID = "__limit__"
        }
        let loadedWarningLightOrangeRuleID: String
        if !storedWarningLightOrangeRuleID.isEmpty {
            loadedWarningLightOrangeRuleID = storedWarningLightOrangeRuleID
        } else if !hasExistingDataLimitConfiguration, loadedWarningRules.indices.contains(1) {
            loadedWarningLightOrangeRuleID = loadedWarningRules[1].id.uuidString
        } else {
            // New per-colour storage must not infer or rewrite an existing
            // user's preferred yellow/red mapping.
            loadedWarningLightOrangeRuleID = "__off__"
        }
        let normalizedWarningLightIDs = Self.normalizedWarningLightRuleIDs(
            rules: loadedWarningRules,
            yellow: loadedWarningLightYellowRuleID,
            orange: loadedWarningLightOrangeRuleID,
            red: loadedWarningLightRedRuleID
        )
        if normalizedWarningLightIDs.yellow != loadedWarningLightYellowRuleID {
            defaults.set(normalizedWarningLightIDs.yellow, forKey: Keys.dataLimitWarningLightYellowRuleID)
        }
        if normalizedWarningLightIDs.orange != loadedWarningLightOrangeRuleID {
            defaults.set(normalizedWarningLightIDs.orange, forKey: Keys.dataLimitWarningLightOrangeRuleID)
        }
        if normalizedWarningLightIDs.red != loadedWarningLightRedRuleID {
            defaults.set(normalizedWarningLightIDs.red, forKey: Keys.dataLimitWarningLightRedRuleID)
        }

        dataLimitRenewalDay = loadedRenewalDay
        dataRenewalMode = loadedRenewalMode
        dataLimitStartDate = loadedLimitStartDate
        showDataLimitInPopover = defaults.object(forKey: Keys.showDataLimitInPopover) as? Bool ?? true
        showDataLimitInMonitor = defaults.object(forKey: Keys.showDataLimitInMonitor) as? Bool ?? false
        dataLimitDisplayMode = DataLimitDisplayMode(rawValue: defaults.string(forKey: Keys.dataLimitDisplayMode) ?? "") ?? .remaining
        dataLimitWarningEnabled = defaults.object(forKey: Keys.dataLimitWarningEnabled) as? Bool ?? false
        dataLimitWarningLightLinked = defaults.object(forKey: Keys.dataLimitWarningLightLinked) as? Bool ?? false
        dataLimitWarningLightYellowRuleID = normalizedWarningLightIDs.yellow
        dataLimitWarningLightOrangeRuleID = normalizedWarningLightIDs.orange
        dataLimitWarningLightRedRuleID = normalizedWarningLightIDs.red
        dataLimitWarningMode = loadedWarningMode
        dataLimitWarningPercentage = loadedWarningPercentage
        dataLimitWarningRemainingValue = loadedWarningRemainingValue
        dataLimitWarningRemainingUnit = loadedWarningRemainingUnit

        let calendar = Calendar.current
        let now = Date()
        dataLimitSelectedEndMonth = min(12, max(1, defaults.object(forKey: Keys.dataLimitSelectedEndMonth) as? Int ?? calendar.component(.month, from: loadedLimitStartDate)))
        dataLimitMonthlyStartDay = min(31, max(1, defaults.object(forKey: Keys.dataLimitMonthlyStartDay) as? Int ?? calendar.component(.day, from: loadedLimitStartDate)))
        let hasNewPeriodSettings = defaults.object(forKey: Keys.dataLimitPeriodMode) != nil
        if hasNewPeriodSettings {
            let loadedPeriodMode = DataLimitPeriodMode(rawValue: defaults.string(forKey: Keys.dataLimitPeriodMode) ?? "") ?? .duration
            let loadedPeriodValue = max(1, defaults.object(forKey: Keys.dataLimitPeriodValue) as? Int ?? 1)
            let loadedPeriodUnit = DataLimitPeriodUnit(rawValue: defaults.string(forKey: Keys.dataLimitPeriodUnit) ?? "") ?? .months
            let loadedEndDate = defaults.object(forKey: Keys.dataLimitEndDate) as? Date
                ?? calendar.date(byAdding: .month, value: 1, to: loadedLimitStartDate)
                ?? now
            let loadedEndBehavior = DataLimitEndBehavior(rawValue: defaults.string(forKey: Keys.dataLimitEndBehavior) ?? "") ?? .repeatSame

            dataLimitPeriodMode = loadedPeriodMode
            dataLimitPeriodValue = loadedPeriodValue
            dataLimitPeriodUnit = loadedPeriodUnit
            dataLimitEndDate = loadedEndDate
            dataLimitEndBehavior = loadedEndBehavior
        } else {
            // Migrate the former monthly-renewal model into the new explicit period model.
            let day = loadedRenewalDay
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
            let monthDays = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? day
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.day = min(day, monthDays)
            let thisMonth = calendar.date(from: comps) ?? monthStart
            let migratedStart: Date
            if thisMonth <= now {
                migratedStart = thisMonth
            } else {
                let previous = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
                let previousDays = calendar.range(of: .day, in: .month, for: previous)?.count ?? day
                var previousComps = calendar.dateComponents([.year, .month], from: previous)
                previousComps.day = min(day, previousDays)
                migratedStart = calendar.date(from: previousComps) ?? previous
            }

            let migratedLimitStartDate = loadedRenewalMode == .monthly ? migratedStart : loadedLimitStartDate
            let migratedEndDate = calendar.date(byAdding: .month, value: 1, to: migratedLimitStartDate)
                ?? now.addingTimeInterval(30 * 86400)

            dataLimitStartDate = migratedLimitStartDate
            dataLimitPeriodMode = .duration
            dataLimitPeriodValue = 1
            dataLimitPeriodUnit = .months
            dataLimitEndDate = migratedEndDate
            dataLimitEndBehavior = loadedRenewalMode == .monthly ? .repeatSame : .stop
        }
        dataLimitReachedAction = DataLimitReachedAction(rawValue: defaults.string(forKey: Keys.dataLimitReachedAction) ?? "") ?? .continueData
        dataLimitStartingRemainingBytes = max(0, defaults.object(forKey: Keys.dataLimitStartingRemainingBytes) as? Double ?? 0)
        dataLimitStartingRemainingApplied = defaults.object(forKey: Keys.dataLimitStartingRemainingApplied) as? Bool ?? false
        dataLimitWarningRules = loadedWarningRules
        dataLimitWarningRepeatMinutes = max(0, defaults.object(forKey: Keys.dataLimitWarningRepeatMinutes) as? Int ?? 0)

        sessionEnabled = defaults.object(forKey: Keys.sessionEnabled) as? Bool ?? false
        showSessionInPopover = defaults.object(forKey: Keys.showSessionInPopover) as? Bool ?? false
        sessionStartDate = defaults.object(forKey: Keys.sessionStartDate) as? Date ?? Date()
        sessionStartMode = SessionStartMode(rawValue: defaults.string(forKey: Keys.sessionStartMode) ?? "") ?? .now
        scheduledSessionStartDate = defaults.object(forKey: Keys.scheduledSessionStartDate) as? Date ?? Date()
        scheduledSessionEndMode = SessionScheduleEndMode(rawValue: defaults.string(forKey: Keys.scheduledSessionEndMode) ?? "") ?? .endDate
        scheduledSessionEndDate = defaults.object(forKey: Keys.scheduledSessionEndDate) as? Date ?? Date().addingTimeInterval(3600)
        scheduledSessionDurationMinutes = max(1, defaults.object(forKey: Keys.scheduledSessionDurationMinutes) as? Int ?? 60)
        sessionFollowsDataRenewal = defaults.object(forKey: Keys.sessionFollowsDataRenewal) as? Bool ?? false

        alwaysOnTopMonitor = defaults.object(forKey: Keys.alwaysOnTopMonitor) as? Bool ?? false
        monitorShowTotalSpeed = defaults.object(forKey: Keys.monitorShowTotalSpeed) as? Bool ?? false
        monitorShowNetwork = defaults.object(forKey: Keys.monitorShowNetwork) as? Bool ?? false
        monitorShowData = defaults.object(forKey: Keys.monitorShowData) as? Bool ?? false
        monitorShowControls = defaults.object(forKey: Keys.monitorShowControls) as? Bool ?? false
    }

    var dataLimitBytes: UInt64 {
        let bytes = max(0, dataLimitValue) * dataLimitUnit.byteMultiplier
        return UInt64(min(bytes, Double(UInt64.max)))
    }

    private func saveWarningRules() {
        guard let data = try? JSONEncoder().encode(dataLimitWarningRules) else { return }
        defaults.set(data, forKey: Keys.dataLimitWarningRules)
    }

    static func normalizedWarningLightRuleIDs(rules: [DataLimitWarningRule],
                                              yellow: String,
                                              orange: String,
                                              red: String) -> (yellow: String, orange: String, red: String) {
        let off = "__off__"
        let limit = "__limit__"
        guard let first = rules.first else { return (off, off, off) }

        let warningIDs = rules.map { $0.id.uuidString }
        let warningIndex = Dictionary(uniqueKeysWithValues: warningIDs.enumerated().map { ($0.element, $0.offset) })
        let limitStage = rules.count

        // Yellow is the first severity color and may point only to a warning
        // milestone (or be off). Preserve an existing valid choice; otherwise
        // fall back to the first warning as earlier builds did.
        let normalizedYellow = (yellow == off || warningIndex[yellow] != nil) ? yellow : first.id.uuidString

        func stage(_ identifier: String, allowsLimit: Bool) -> Int? {
            if identifier == off { return nil }
            if allowsLimit, identifier == limit { return limitStage }
            return warningIndex[identifier]
        }

        var normalizedOrange = (orange == off || orange == limit || warningIndex[orange] != nil) ? orange : off
        var normalizedRed = (red == off || red == limit || warningIndex[red] != nil) ? red : limit

        var highestStage = stage(normalizedYellow, allowsLimit: false)

        if let orangeStage = stage(normalizedOrange, allowsLimit: true) {
            if let highestStage, orangeStage <= highestStage {
                // An invalid later color is turned off rather than silently
                // moving the user's mapping to a different warning milestone.
                normalizedOrange = off
            } else {
                highestStage = orangeStage
            }
        }

        if let redStage = stage(normalizedRed, allowsLimit: true) {
            if let highestStage, redStage <= highestStage {
                // Prefer the hard limit only when it is still strictly later
                // than every active preceding color; otherwise red is off.
                if limitStage > highestStage {
                    normalizedRed = limit
                } else {
                    normalizedRed = off
                }
            }
        }

        return (normalizedYellow, normalizedOrange, normalizedRed)
    }

    var effectivePopoverRefreshIntervalSeconds: Double { popoverUseMenuBarRefresh ? refreshIntervalSeconds : popoverRefreshIntervalSeconds }
    var effectiveMonitorScale: PopoverScale { monitorUsePopoverSettings ? popoverScale : monitorScale }
    var effectiveMonitorShowTotalSpeed: Bool { monitorUsePopoverSettings ? popoverShowTotalSpeed : monitorShowTotalSpeed }
    var effectiveMonitorShowData: Bool {
        (showDataLimitInMonitor || (monitorUsePopoverSettings ? showSessionInPopover : monitorShowData))
    }
    var effectiveMonitorRefreshIntervalSeconds: Double {
        monitorUsePopoverSettings ? effectivePopoverRefreshIntervalSeconds : (monitorUseMenuBarRefresh ? refreshIntervalSeconds : monitorRefreshIntervalSeconds)
    }
    var effectiveMonitorUnitMode: SpeedUnitMode { monitorUsePopoverSettings ? popoverUnitMode : monitorUnitMode }
    var effectiveMonitorProcessDisplay: ProcessDisplayMode { monitorUsePopoverSettings ? popoverProcessDisplay : monitorProcessDisplay }
    var effectiveMonitorDirectionDisplay: TransferDirectionDisplay { monitorUsePopoverSettings ? popoverDirectionDisplay : monitorDirectionDisplay }
    var effectiveMonitorHideInactiveApps: Bool { monitorUsePopoverSettings ? popoverHideInactiveApps : monitorHideInactiveApps }
    var effectiveMonitorInactiveHideDelaySeconds: Double { monitorUsePopoverSettings ? popoverInactiveHideDelaySeconds : monitorInactiveHideDelaySeconds }
    var effectiveMonitorExitMotion: Bool { monitorUsePopoverSettings ? popoverExitMotion : monitorExitMotion }
    var effectiveMonitorSortMode: TrafficSortMode { monitorUsePopoverSettings ? popoverSortMode : monitorSortMode }
    var effectiveMonitorColumns: [StatusColumn] { monitorUsePopoverSettings ? popoverColumns : monitorColumns }
    var effectiveMonitorManualOrder: [String] { monitorUsePopoverSettings ? popoverManualOrder : monitorManualOrder }
    var effectiveMonitorHiddenProcessIDs: [String] { monitorUsePopoverSettings ? popoverHiddenProcessIDs : monitorHiddenProcessIDs }
    var effectiveMonitorGroupSystemProcesses: Bool { monitorUsePopoverSettings ? popoverGroupSystemProcesses : monitorGroupSystemProcesses }
    var effectiveMonitorVisibilityMode: AppVisibilityMode { monitorUsePopoverSettings ? popoverVisibilityMode : monitorVisibilityMode }
    var effectiveMonitorSelectedProcessIDs: [String] { monitorUsePopoverSettings ? popoverSelectedProcessIDs : monitorSelectedProcessIDs }
    var effectiveMonitorHideLowActivityApps: Bool { monitorUsePopoverSettings ? popoverHideLowActivityApps : monitorHideLowActivityApps }
    var effectiveMonitorLowActivityDurationValue: Double { monitorUsePopoverSettings ? popoverLowActivityDurationValue : monitorLowActivityDurationValue }
    var effectiveMonitorLowActivityDurationUnit: LowActivityDurationUnit { monitorUsePopoverSettings ? popoverLowActivityDurationUnit : monitorLowActivityDurationUnit }
    var effectiveMonitorLowActivityDataValue: Double { monitorUsePopoverSettings ? popoverLowActivityDataValue : monitorLowActivityDataValue }
    var effectiveMonitorLowActivityDataUnit: LowActivityDataUnit { monitorUsePopoverSettings ? popoverLowActivityDataUnit : monitorLowActivityDataUnit }
    var effectiveMonitorGroupUnselectedApps: Bool { monitorUsePopoverSettings ? popoverGroupUnselectedApps : monitorGroupUnselectedApps }

    /// The monitor normally follows the popover. When the user explicitly enables
    /// independent monitor settings, start from the popover's *current* values so
    /// they only need to change the few differences they actually want.
    func copyPopoverSettingsToMonitor() {
        monitorScale = popoverScale
        monitorUnitMode = popoverUnitMode
        monitorProcessDisplay = popoverProcessDisplay
        monitorDirectionDisplay = popoverDirectionDisplay
        monitorInactivePolicy = popoverInactivePolicy
        monitorHideInactiveApps = popoverHideInactiveApps
        monitorInactiveHideDelaySeconds = popoverInactiveHideDelaySeconds
        monitorExitMotion = popoverExitMotion
        monitorSortMode = popoverSortMode
        monitorManualOrder = popoverManualOrder
        monitorHiddenProcessIDs = popoverHiddenProcessIDs
        monitorGroupSystemProcesses = popoverGroupSystemProcesses
        monitorVisibilityMode = popoverVisibilityMode
        monitorSelectedProcessIDs = popoverSelectedProcessIDs
        monitorGroupAppleApps = popoverGroupAppleApps
        monitorHideLowActivityApps = popoverHideLowActivityApps
        monitorLowActivityThresholdKBps = popoverLowActivityThresholdKBps
        monitorLowActivityThresholdUnit = popoverLowActivityThresholdUnit
        monitorLowActivityDurationValue = popoverLowActivityDurationValue
        monitorLowActivityDurationUnit = popoverLowActivityDurationUnit
        monitorLowActivityDataValue = popoverLowActivityDataValue
        monitorLowActivityDataUnit = popoverLowActivityDataUnit
        monitorGroupUnselectedApps = popoverGroupUnselectedApps
        monitorColumns = popoverColumns
        monitorRefreshIntervalSeconds = effectivePopoverRefreshIntervalSeconds
        monitorUseMenuBarRefresh = popoverUseMenuBarRefresh
        monitorShowTotalSpeed = popoverShowTotalSpeed
        monitorShowData = showDataLimitInPopover || showSessionInPopover
    }

    var menuBarElements: [MenuBarElement] { menuBarTopElements + menuBarBottomElements }
    var menuBarHasLimitElement: Bool { menuBarElements.contains(where: { $0.isLimitElement }) }

    func setDataLimitVisibleInMenuBar(_ visible: Bool) {
        if visible {
            guard !menuBarHasLimitElement else { return }
            menuBarTopElements.append(.limitValue)
        } else {
            menuBarTopElements.removeAll(where: { $0.isLimitElement })
            menuBarBottomElements.removeAll(where: { $0.isLimitElement })
            ensureMenuBarHasElement()
        }
    }

    func ensureMenuBarHasElement() {
        if menuBarTopElements.isEmpty && menuBarBottomElements.isEmpty {
            menuBarTopElements = [.downloadValue]
        }
    }

    func setMenuBarElement(_ element: MenuBarElement, visible: Bool) {
        if visible {
            guard !menuBarElements.contains(element) else { return }
            menuBarTopElements.append(element)
        } else {
            guard menuBarElements.count > 1 else { return }
            menuBarTopElements.removeAll { $0 == element }
            menuBarBottomElements.removeAll { $0 == element }
        }
    }

    func moveMenuBarElement(_ element: MenuBarElement, toTopRow top: Bool, before target: MenuBarElement? = nil) {
        menuBarTopElements.removeAll { $0 == element }
        menuBarBottomElements.removeAll { $0 == element }
        var row = top ? menuBarTopElements : menuBarBottomElements
        if let target, let index = row.firstIndex(of: target) { row.insert(element, at: index) } else { row.append(element) }
        if top { menuBarTopElements = row } else { menuBarBottomElements = row }
    }

    private static func loadMenuBarElements(_ raw: [String]?, fallback: [MenuBarElement]) -> [MenuBarElement] {
        guard let raw else { return fallback }
        var seen = Set<MenuBarElement>()
        return raw.compactMap(MenuBarElement.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    private static func normalizeMenuBarLayout(top: [MenuBarElement], bottom: [MenuBarElement]) -> (top: [MenuBarElement], bottom: [MenuBarElement]) {
        var used = Set<MenuBarElement>()
        let normalizedTop = top.filter { used.insert($0).inserted }
        let normalizedBottom = bottom.filter { used.insert($0).inserted }
        if normalizedTop.isEmpty && normalizedBottom.isEmpty {
            return ([.uploadArrow, .uploadValue], [.downloadArrow, .downloadValue])
        }
        return (normalizedTop, normalizedBottom)
    }

    func restoreAdvancedMenuDefaults() {
        menuFontFamily = ""
        menuFontSize = Self.defaultMenuFontSize
        valueAreaWidth = 28.0
        iconAreaWidth = 8.0
        metricGap = 5.0
        rowSpacing = 0.5
    }

    func moveManualProcess(_ sourceID: String, before targetID: String, monitor: Bool) {
        var order = monitor && !monitorUsePopoverSettings ? monitorManualOrder : popoverManualOrder
        order.removeAll { $0 == sourceID }
        if let targetIndex = order.firstIndex(of: targetID) {
            order.insert(sourceID, at: targetIndex)
        } else {
            order.append(sourceID)
        }
        if monitor && !monitorUsePopoverSettings { monitorManualOrder = order } else { popoverManualOrder = order }
    }

    func ensureManualOrderContains(_ ids: [String], monitor: Bool) {
        var order = monitor && !monitorUsePopoverSettings ? monitorManualOrder : popoverManualOrder
        let existing = Set(order)
        order.append(contentsOf: ids.filter { !existing.contains($0) })
        if monitor && !monitorUsePopoverSettings {
            if order != monitorManualOrder { monitorManualOrder = order }
        } else if order != popoverManualOrder {
            popoverManualOrder = order
        }
    }

    func setProcessHidden(_ id: String, hidden: Bool, monitor: Bool) {
        var values = monitor && !monitorUsePopoverSettings ? monitorHiddenProcessIDs : popoverHiddenProcessIDs
        values.removeAll { $0 == id }
        if hidden { values.append(id) }
        if monitor && !monitorUsePopoverSettings { monitorHiddenProcessIDs = values } else { popoverHiddenProcessIDs = values }
    }

    func setDetailProcessHidden(_ id: String, hidden: Bool) {
        var values = hiddenDetailProcessIDs
        values.removeAll { $0 == id }
        if hidden { values.append(id) }
        hiddenDetailProcessIDs = values
    }

    func setProcessSelected(_ id: String, selected: Bool, monitor: Bool) {
        var values = monitor && !monitorUsePopoverSettings ? monitorSelectedProcessIDs : popoverSelectedProcessIDs
        values.removeAll { $0 == id }
        if selected { values.append(id) }
        if monitor && !monitorUsePopoverSettings { monitorSelectedProcessIDs = values } else { popoverSelectedProcessIDs = values }
    }

    func saveTrafficOrderPreset(name: String, order: [String]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = trafficOrderPresets.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            trafficOrderPresets[index].order = order
        } else {
            trafficOrderPresets.append(TrafficOrderPreset(name: trimmed, order: order))
        }
    }

    func deleteTrafficOrderPreset(id: String) {
        trafficOrderPresets.removeAll { $0.id == id }
    }

    func applyTrafficOrderPreset(id: String, monitor: Bool) {
        guard let preset = trafficOrderPresets.first(where: { $0.id == id }) else { return }
        if monitor && !monitorUsePopoverSettings { monitorManualOrder = preset.order } else { popoverManualOrder = preset.order }
    }

    func setManualParentApp(_ bundleIdentifier: String?, for usage: AppNetworkUsage) {
        guard let key = manualParentMappingKey(for: usage) else { return }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            manualParentAppMappings[key] = bundleIdentifier
        } else {
            manualParentAppMappings.removeValue(forKey: key)
        }
    }

    func manualParentMapping(for usage: AppNetworkUsage) -> String? {
        guard let key = manualParentMappingKey(for: usage) else { return nil }
        return manualParentAppMappings[key]
    }

    private func manualParentMappingKey(for usage: AppNetworkUsage) -> String? {
        if let process = usage.processIdentifier, !process.isEmpty { return process }
        if usage.isSystemProcess && !usage.id.isEmpty { return usage.id }
        return nil
    }

    func setStatusColumnVisible(_ column: StatusColumn, visible: Bool, monitor: Bool) {
        guard column != .process else { return }
        var columns = monitor && !monitorUsePopoverSettings ? monitorColumns : popoverColumns
        columns.removeAll { $0 == column }
        if visible { columns.append(column) }
        if !columns.contains(.process) { columns.insert(.process, at: 0) }
        if monitor && !monitorUsePopoverSettings { monitorColumns = columns } else { popoverColumns = columns }
    }

    func moveStatusColumn(_ column: StatusColumn, before target: StatusColumn, monitor: Bool) {
        var columns = monitor && !monitorUsePopoverSettings ? monitorColumns : popoverColumns
        guard let from = columns.firstIndex(of: column), let to = columns.firstIndex(of: target), from != to else { return }
        let item = columns.remove(at: from)
        let adjusted = columns.firstIndex(of: target) ?? min(to, columns.count)
        columns.insert(item, at: adjusted)
        if !columns.contains(.process) { columns.insert(.process, at: 0) }
        if monitor && !monitorUsePopoverSettings { monitorColumns = columns } else { popoverColumns = columns }
    }

    private static func loadColumns(_ raw: [String]?) -> [StatusColumn] {
        var values = (raw ?? []).compactMap(StatusColumn.init(rawValue:))
        if values.isEmpty { values = StatusColumn.defaultColumns }
        values = Array(NSOrderedSet(array: values.map(\.rawValue))).compactMap { ($0 as? String).flatMap(StatusColumn.init(rawValue:)) }
        if !values.contains(.process) { values.insert(.process, at: 0) }
        return values
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(trafficOrderPresets) else { return }
        defaults.set(data, forKey: Keys.trafficOrderPresets)
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
    private func normalizedInterval(_ value: Double) -> Double { Self.normalizeInterval(value) }

    static func normalizeInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 3.0 }
        if value <= 0.25 { return 0.25 }
        return max(0.25, (value * 10).rounded() / 10)
    }

    static func normalizeClosedDataRetention(_ value: Double) -> Double {
        guard value.isFinite else { return 5.0 }
        return max(0, (value * 10).rounded() / 10)
    }

    static func normalizeInactiveHideDelay(_ value: Double) -> Double {
        guard value.isFinite else { return 10.0 }
        return min(3600.0, max(0.0, value))
    }

    static func parseClosedDataRetentionText(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["seconds", "second", "secs", "sec", "s", "초"] {
            if value.hasSuffix(suffix) {
                value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        value = value.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(value), parsed.isFinite, parsed >= 0 else { return nil }
        return normalizeClosedDataRetention(parsed)
    }

    static func normalizeLowActivityThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        // Store in KB/s with 0.001 KB precision so B/s display values remain
        // stable across relaunches while every UI unit maps to one comparison base.
        return max(0.001, (value * 1000).rounded() / 1000)
    }

    static func normalizeLowActivityDuration(_ value: Double) -> Double {
        guard value.isFinite else { return 5.0 }
        // The unit (minutes/hours) is stored separately. Zero has no meaningful
        // observation window, so keep at least one selected unit. A generous cap
        // prevents accidental huge inputs while still allowing long expert windows.
        let clamped = min(10_080.0, max(1.0, value))
        return (clamped * 10.0).rounded() / 10.0
    }

    static func normalizeLowActivityData(_ value: Double) -> Double {
        guard value.isFinite else { return 100.0 }
        // The unit (KB/MB/GB) is stored separately. Zero is valid and means
        // "no transferred bytes during the selected window".
        let clamped = min(1_000_000.0, max(0.0, value))
        return (clamped * 100.0).rounded() / 100.0
    }

    static func parseIntervalText(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["seconds", "second", "secs", "sec", "s", "초"] {
            if value.hasSuffix(suffix) {
                value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        value = value.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(value), parsed.isFinite, parsed >= 0.25 else { return nil }
        return normalizeInterval(parsed)
    }

    private enum Keys {
        static let showDownload = "menu.showDownload"
        static let showUpload = "menu.showUpload"
        static let metricOrder = "menu.metricOrder"
        static let menuDisplayStyle = "menu.displayStyle"
        static let showIcons = "menu.showIcons"
        static let menuBarTopElements = "menu.layout.topElements.v1"
        static let menuBarBottomElements = "menu.layout.bottomElements.v1"
        static let unitMode = "menu.unitMode"
        static let refreshDefaultsVersion = "refresh.defaultsVersion"
        static let refreshInterval = "monitor.refreshIntervalSeconds"
        static let popoverRefreshInterval = "popover.refreshIntervalSeconds"
        static let popoverUseMenuBarRefresh = "popover.useMenuBarRefresh"
        static let monitorUseMenuBarRefresh = "monitor.useMenuBarRefresh"
        static let popoverClosedDataRetention = "popover.closedDataRetentionSeconds"
        static let monitorRefreshInterval = "monitorWindow.refreshIntervalSeconds"
        static let appearance = "appearance"
        static let accentMode = "appearance.accentMode"
        static let customAccentHex = "appearance.customAccentHex"
        static let language = "language"
        static let settingsWindowSizeMode = "general.settingsWindowSizeMode"
        static let showDetailedDescriptions = "general.showDetailedDescriptions"
        static let resourceMode = "general.resourceMode"
        static let austerityKeepTotalHistory = "general.austerityKeepTotalHistory"
        static let expertFeaturesEnabled = "general.expertFeaturesEnabled"
        static let profiles = "general.profilesV1"
        static let menuFontFamily = "menu.fontFamily"
        static let menuFontSize = "menu.fontSize"
        static let valueAreaWidth = "menu.valueAreaWidth"
        static let iconAreaWidth = "menu.iconAreaWidth"
        static let metricGap = "menu.metricGap"
        static let rowSpacing = "menu.rowSpacing"
        static let menuSizingVersion = "menu.sizingVersion"
        static let popoverScale = "popover.scale"
        static let popoverUnitMode = "popover.unitMode"
        static let popoverProcessDisplay = "popover.processDisplay"
        static let popoverDirectionDisplay = "popover.directionDisplay"
        static let popoverInactivePolicy = "popover.inactivePolicy"
        static let popoverHideInactiveApps = "popover.hideInactiveApps"
        static let popoverInactiveHideDelaySeconds = "popover.inactiveHideDelaySeconds"
        static let popoverExitMotion = "popover.exitMotion"
        static let popoverSortMode = "popover.sortMode"
        static let popoverShowControls = "popover.showControls"
        static let popoverShowTotalSpeed = "popover.showTotalSpeed"
        static let popoverManualOrder = "popover.manualOrder"
        static let popoverHiddenProcessIDs = "popover.hiddenProcessIDs"
        static let popoverGroupSystemProcesses = "popover.groupSystemProcesses"
        static let popoverVisibilityMode = "popover.visibilityMode"
        static let popoverSelectedProcessIDs = "popover.selectedProcessIDs"
        static let popoverGroupAppleApps = "popover.groupAppleApps"
        static let popoverHideLowActivityApps = "popover.hideLowActivityApps"
        static let popoverLowActivityThresholdKBps = "popover.lowActivityThresholdKBps"
        static let popoverLowActivityThresholdUnit = "popover.lowActivityThresholdUnit"
        static let popoverLowActivityDurationValue = "popover.lowActivity.durationValue"
        static let popoverLowActivityDurationUnit = "popover.lowActivity.durationUnit"
        static let popoverLowActivityDataValue = "popover.lowActivity.dataValue"
        static let popoverLowActivityDataUnit = "popover.lowActivity.dataUnit"
        static let popoverGroupUnselectedApps = "popover.groupUnselectedApps"
        static let advancedProcessControlsEnabled = "status.advancedProcessControlsEnabled"
        static let hiddenDetailProcessIDs = "status.hiddenDetailProcessIDs"
        static let manualParentAppMappings = "status.manualParentAppMappingsV1"
        static let popoverColumns = "popover.columns"
        static let trafficOrderPresets = "popover.orderPresets"
        static let monitorUsePopoverSettings = "monitor.usePopoverSettings"
        static let monitorScale = "monitor.scale"
        static let monitorUnitMode = "monitor.unitMode"
        static let monitorProcessDisplay = "monitor.processDisplay"
        static let monitorDirectionDisplay = "monitor.directionDisplay"
        static let monitorInactivePolicy = "monitor.inactivePolicy"
        static let monitorHideInactiveApps = "monitor.hideInactiveApps"
        static let monitorInactiveHideDelaySeconds = "monitor.inactiveHideDelaySeconds"
        static let monitorExitMotion = "monitor.exitMotion"
        static let monitorSortMode = "monitor.sortMode"
        static let monitorManualOrder = "monitor.manualOrder"
        static let monitorHiddenProcessIDs = "monitor.hiddenProcessIDs"
        static let monitorGroupSystemProcesses = "monitor.groupSystemProcesses"
        static let monitorVisibilityMode = "monitor.visibilityMode"
        static let monitorSelectedProcessIDs = "monitor.selectedProcessIDs"
        static let monitorGroupAppleApps = "monitor.groupAppleApps"
        static let monitorHideLowActivityApps = "monitor.hideLowActivityApps"
        static let monitorLowActivityThresholdKBps = "monitor.lowActivityThresholdKBps"
        static let monitorLowActivityThresholdUnit = "monitor.lowActivityThresholdUnit"
        static let monitorLowActivityDurationValue = "monitor.lowActivity.durationValue"
        static let monitorLowActivityDurationUnit = "monitor.lowActivity.durationUnit"
        static let monitorLowActivityDataValue = "monitor.lowActivity.dataValue"
        static let monitorLowActivityDataUnit = "monitor.lowActivity.dataUnit"
        static let monitorGroupUnselectedApps = "monitor.groupUnselectedApps"
        static let monitorColumns = "monitor.columns"
        static let recordingMode = "history.recordingMode"
        static let processDetailRecordingEnabled = "history.processDetailRecordingEnabled"
        static let retentionDays = "history.retentionDays"
        static let separateLocalTraffic = "network.separateLocalTraffic"
        static let localTrafficStatisticsMode = "network.localTrafficStatisticsMode"
        static let dataLimitTrafficScope = "network.dataLimitTrafficScope"
        static let dataLimitNetworkTargetMode = "data.limitNetworkTargetMode"
        static let dataLimitNetworkIdentifier = "data.limitNetworkIdentifier"
        static let dataLimitNetworkDisplayName = "data.limitNetworkDisplayName"
        static let menuBarTrafficScope = "network.menuBarTrafficScope"
        static let dataLimitEnabled = "data.limitEnabled"
        static let dataLimitValue = "data.limitValue"
        static let dataLimitUnit = "data.limitUnit"
        static let legacyDataLimitGB = "data.limitGB"
        static let dataLimitRenewalDay = "data.renewalDay"
        static let dataRenewalMode = "data.renewalMode"
        static let dataLimitStartDate = "data.limitStartDate"
        static let showDataLimitInPopover = "data.showLimitInPopover"
        static let showDataLimitInMonitor = "data.showLimitInMonitor"
        static let dataLimitDisplayMode = "data.limitDisplayMode"
        static let dataLimitWarningEnabled = "data.limitWarningEnabled"
        static let dataLimitWarningLightLinked = "data.limitWarningLightLinked"
        static let dataLimitWarningLightYellowRuleID = "data.limitWarningLightYellowRuleID"
        static let dataLimitWarningLightOrangeRuleID = "data.limitWarningLightOrangeRuleID"
        static let dataLimitWarningLightRedRuleID = "data.limitWarningLightRedRuleID"
        static let dataLimitWarningMode = "data.limitWarningMode"
        static let dataLimitWarningPercentage = "data.limitWarningPercentage"
        static let dataLimitWarningRemainingValue = "data.limitWarningRemainingValue"
        static let dataLimitWarningRemainingUnit = "data.limitWarningRemainingUnit"
        static let dataLimitPeriodMode = "data.limitPeriodMode"
        static let dataLimitPeriodValue = "data.limitPeriodValue"
        static let dataLimitPeriodUnit = "data.limitPeriodUnit"
        static let dataLimitSelectedEndMonth = "data.limitSelectedEndMonth"
        static let dataLimitEndDate = "data.limitEndDate"
        static let dataLimitEndBehavior = "data.limitEndBehavior"
        static let dataLimitMonthlyStartDay = "data.limitMonthlyStartDay"
        static let dataLimitReachedAction = "data.limitReachedAction"
        static let dataLimitStartingRemainingBytes = "data.limitStartingRemainingBytes"
        static let dataLimitStartingRemainingApplied = "data.limitStartingRemainingApplied"
        static let dataLimitWarningRules = "data.limitWarningRulesV2"
        static let dataLimitWarningRepeatMinutes = "data.limitWarningRepeatMinutes"
        static let sessionEnabled = "data.sessionEnabled"
        static let showSessionInPopover = "data.showSessionInPopover"
        static let sessionStartDate = "data.sessionStartDate"
        static let sessionStartMode = "data.sessionStartMode"
        static let scheduledSessionStartDate = "data.scheduledSessionStartDate"
        static let scheduledSessionEndMode = "data.scheduledSessionEndMode"
        static let scheduledSessionEndDate = "data.scheduledSessionEndDate"
        static let scheduledSessionDurationMinutes = "data.scheduledSessionDurationMinutes"
        static let sessionFollowsDataRenewal = "data.sessionFollowsDataRenewal"
        static let alwaysOnTopMonitor = "monitor.alwaysOnTop"
        static let monitorShowTotalSpeed = "monitor.showTotalSpeed"
        static let monitorShowNetwork = "monitor.showNetwork"
        static let monitorShowData = "monitor.showData"
        static let monitorShowControls = "monitor.showControls"
    }
}
