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
    /// Schema 10 keeps the aggregate traffic snapshot shape while adding shared
    /// signed-Host XPC liveness as the fail-open gate for app/Data Limit blocking.
    /// An older provider must not be trusted for that safety contract.
    static let trafficSnapshotSchemaVersion = 10
    static let processHierarchySchemaVersion = 2
    static let extensionRequestedSchemaDefaultsKey = "systemExtension.requestedTrafficSchemaVersion"
    static let extensionActiveSchemaDefaultsKey = "systemExtension.activeTrafficSchemaVersion"

    /// The App Group uses Apple's registered `group.` form, so the XPC name can
    /// remain stable across development teams without embedding a private Team ID.
    static var trafficMachServiceName: String {
        Bundle.main.object(forInfoDictionaryKey: "NeManeemTrafficMachServiceName") as? String ?? ""
    }
}
