import Foundation

enum AppConstants {
    static let appBundleIdentifier = "com.bak2ya.NeManeem"
    static let filterBundleIdentifier = "com.bak2ya.NeManeem.Filter"
    static let applicationGroupIdentifier = "group.com.bak2ya.NeManeem"
    static let blockedAppsConfigurationKey = "blockedBundleIdentifiers"
    static let blockedProcessesConfigurationKey = "blockedProcessIdentifiers"
    static let blockingEnabledConfigurationKey = "blockingEnabled"
    static let processBlockingEnabledConfigurationKey = "processBlockingEnabled"
    static let dataLimitInternetBlockConfigurationKey = "dataLimitInternetBlocked"
    static let dataLimitBlockLeaseExpiryConfigurationKey = "dataLimitBlockLeaseExpiresAt"
    static let safariNetworkServiceGroupingConfigurationKey = "safariNetworkServiceGroupingEnabled"
    static let safariNetworkServiceGroupingDefaultsKey = "network.safariNetworkServiceGroupingEnabled"
    /// Schema 9 keeps the same traffic snapshot wire shape while adding the explicit
    /// code-signing process-block policy bits used by the data provider. Bumping the
    /// generation ensures an older provider cannot silently ignore that policy.
    static let trafficSnapshotSchemaVersion = 9
    static let processHierarchySchemaVersion = 2
    static let extensionRequestedSchemaDefaultsKey = "systemExtension.requestedTrafficSchemaVersion"
    static let extensionActiveSchemaDefaultsKey = "systemExtension.activeTrafficSchemaVersion"

    /// The App Group uses Apple's registered `group.` form, so the XPC name can
    /// remain stable across development teams without embedding a private Team ID.
    static var trafficMachServiceName: String {
        Bundle.main.object(forInfoDictionaryKey: "NeManeemTrafficMachServiceName") as? String ?? ""
    }
}
