import Foundation
import NetworkExtension
import SystemExtensions
import OSLog

/// Keeps NeManeem's Network Extension enabled as the single measurement engine.
/// `isEnabled` represents only the user's app-blocking policy; turning blocking
/// off never tears down traffic measurement.
@MainActor
final class FirewallController: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.bak2ya.NeManeem", category: "NetworkExtension")
    @Published private(set) var isEnabled = false
    @Published private(set) var engineIsEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var extensionNeedsUserApproval = false
    @Published private(set) var monitoringPermissionRequestRecommended = false
    @Published private(set) var blockedBundleIdentifiers: Set<String> = []
    @Published private(set) var blockedProcessIdentifiers: Set<String> = []
    @Published private(set) var processBlockingEnabled = false
    @Published private(set) var isDataLimitInternetBlocked = false

    private let manager = NEFilterManager.shared()
    private let extensionController = SystemExtensionController()
    private let blockedDefaultsKey = "firewall.blockedBundleIdentifiers"
    private let blockedProcessesDefaultsKey = "firewall.blockedProcessIdentifiers"
    private let processBlockingEnabledDefaultsKey = "firewall.processBlockingEnabled"
    private var hasLoadedPreferences = false
    private var activationInFlight = false
    private var monitoringPermissionRequestPendingAfterLoad = false
    private var removalInProgress = false
    /// Identifies the one user-visible removal preparation that is currently
    /// allowed to update state.  Invalidating it lets the user leave a stalled
    /// macOS request without attempting to undo work that already completed.
    private var removalOperationID: UUID?
    private var filterReconfigurationStartedAt: Date?
    // Legacy vendor field kept at zero so an older stored configuration remains
    // comparable during migration. Build 143+ fail-open safety uses shared Host XPC
    // liveness instead of repeatedly rewriting Network Extension preferences.
    private var dataLimitBlockLeaseExpiresAt: TimeInterval = 0

    override init() {
        super.init()
        blockedBundleIdentifiers = Set(UserDefaults.standard.stringArray(forKey: blockedDefaultsKey) ?? [])
            .filter { !Self.isProtectedNeManeemIdentifier($0) }
        blockedProcessIdentifiers = Set(UserDefaults.standard.stringArray(forKey: blockedProcessesDefaultsKey) ?? [])
            .filter { Self.isBlockableProcessIdentifier($0) }
        processBlockingEnabled = UserDefaults.standard.bool(forKey: processBlockingEnabledDefaultsKey)
        UserDefaults.standard.set(Array(blockedBundleIdentifiers).sorted(), forKey: blockedDefaultsKey)
        UserDefaults.standard.set(Array(blockedProcessIdentifiers).sorted(), forKey: blockedProcessesDefaultsKey)
        extensionController.onNeedsUserApproval = { [weak self] in
            Task { @MainActor in
                guard let self, !self.removalInProgress else { return }
                self.extensionNeedsUserApproval = true
                self.monitoringPermissionRequestRecommended = false
                // macOS is now waiting for the user's explicit approval, not for
                // an in-app operation. Surface the System Settings action instead
                // of leaving the permission card in a disabled busy state.
                self.activationInFlight = false
                self.isBusy = false
            }
        }
    }

    /// Loads the current policy. Existing authorized engines are kept active; a
    /// clean/disabled install waits for an explicit user permission action.
    func loadStatus() {
        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.hasLoadedPreferences = true
                if let error {
                    self.statusMessage = error.localizedDescription
                    self.engineIsEnabled = false
                    self.isBusy = false
                    self.monitoringPermissionRequestPendingAfterLoad = false
                    return
                }

                let configuration = self.manager.providerConfiguration
                let providerMatches = configuration?.filterDataProviderBundleIdentifier == AppConstants.filterBundleIdentifier
                let socketsEnabled = configuration?.filterSockets ?? false
                self.engineIsEnabled = self.manager.isEnabled && providerMatches && socketsEnabled
                if self.engineIsEnabled { self.extensionNeedsUserApproval = false }
                Self.logger.notice("Loaded filter preferences enabled=\(self.manager.isEnabled, privacy: .public) providerMatches=\(providerMatches, privacy: .public) socketsEnabled=\(socketsEnabled, privacy: .public)")
                let vendor = configuration?.vendorConfiguration ?? [:]
                // Migration: before 0.3.7 the filter's enabled state also meant
                // "blocking enabled". Preserve that choice if the new key is absent.
                self.isEnabled = vendor[AppConstants.blockingEnabledConfigurationKey] as? Bool
                    ?? self.manager.isEnabled
                self.processBlockingEnabled = vendor[AppConstants.processBlockingEnabledConfigurationKey] as? Bool
                    ?? self.processBlockingEnabled
                let storedBlock = vendor[AppConstants.dataLimitInternetBlockConfigurationKey] as? Bool ?? false
                // Never revive a block from a previous Host process. A new launch
                // starts fail-open; UsageRecorder may arm the block again only after
                // re-validating the current limit cycle and target network.
                self.isDataLimitInternetBlocked = false
                self.dataLimitBlockLeaseExpiresAt = 0
                self.statusMessage = nil
                if storedBlock && self.engineIsEnabled {
                    self.saveVendorConfiguration(blockingEnabled: self.isEnabled, completion: nil)
                }

                // 0.4 snapshot schema 2 is the first version that can expose the
                // owning app and its source process separately. Request replacement
                // once when an older extension is active, but do not submit the same
                // request on every launch while macOS is waiting for reboot/approval.
                let defaults = UserDefaults.standard
                let activeSchema = defaults.integer(forKey: AppConstants.extensionActiveSchemaDefaultsKey)
                let requestedSchema = defaults.integer(forKey: AppConstants.extensionRequestedSchemaDefaultsKey)
                let extensionUpdateNeeded = activeSchema < AppConstants.trafficSnapshotSchemaVersion &&
                    requestedSchema < AppConstants.trafficSnapshotSchemaVersion

                if self.engineIsEnabled {
                    self.monitoringPermissionRequestRecommended = false
                    if !extensionUpdateNeeded {
                        self.isBusy = false
                        Self.logger.notice("Existing monitoring engine accepted without replacement request activeSchema=\(activeSchema, privacy: .public) requestedSchema=\(requestedSchema, privacy: .public)")
                    } else {
                        // Updating an already-authorized engine is maintenance, not a
                        // first-run permission request, so it may proceed automatically.
                        self.ensureMonitoringEngineEnabled()
                    }
                } else {
                    // On a clean/disabled installation, wait for an explicit user
                    // action before asking macOS to activate/configure the filter.
                    // This keeps the native content-filter approval prompt tied to
                    // a visible user action and provides a reliable retry path.
                    self.isBusy = false
                    self.monitoringPermissionRequestRecommended = true
                    Self.logger.notice("Monitoring permission/user action required before enabling filter")
                }
                self.continueMonitoringPermissionRequestAfterLoadIfNeeded()
            }
        }
    }

    /// Re-checks the saved Network Extension state without activating, replacing,
    /// enabling, disabling, or saving any system/network-extension preference.
    /// Persistent XPC reconnect episodes use this passive path so a temporary
    /// measurement connection failure never causes a second network reconfiguration.
    func refreshEngineStatusWithoutReconfiguration() {
        guard hasLoadedPreferences else { return }
        Self.logger.notice("Passive filter status refresh started; no Network Extension preferences will be changed")
        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = error.localizedDescription
                    Self.logger.error("Passive filter status refresh failed")
                    return
                }
                let configuration = self.manager.providerConfiguration
                let providerMatches = configuration?.filterDataProviderBundleIdentifier == AppConstants.filterBundleIdentifier
                let socketsEnabled = configuration?.filterSockets ?? false
                self.engineIsEnabled = self.manager.isEnabled && providerMatches && socketsEnabled
                if self.engineIsEnabled {
                    self.extensionNeedsUserApproval = false
                    self.monitoringPermissionRequestRecommended = false
                    self.statusMessage = nil
                } else {
                    self.monitoringPermissionRequestRecommended = true
                }
                Self.logger.notice("Passive filter status refresh completed enabled=\(self.manager.isEnabled, privacy: .public) providerMatches=\(providerMatches, privacy: .public) socketsEnabled=\(socketsEnabled, privacy: .public)")
            }
        }
    }

    /// User-initiated entry point for the native System Extension/content-filter
    /// approval flow. Keeping this separate from background retries prevents launch
    /// races from being the only chance to see macOS's approval UI.
    func requestMonitoringPermission() {
        guard !removalInProgress else { return }
        monitoringPermissionRequestPendingAfterLoad = true
        guard hasLoadedPreferences else {
            isBusy = true
            statusMessage = nil
            loadStatus()
            return
        }
        continueMonitoringPermissionRequestAfterLoadIfNeeded()
    }

    /// A permission click that arrives while preferences are still loading must
    /// continue after that load; requiring a second click makes the first action
    /// appear broken and disconnects the native prompt from the user's intent.
    private func continueMonitoringPermissionRequestAfterLoadIfNeeded() {
        guard monitoringPermissionRequestPendingAfterLoad else { return }
        monitoringPermissionRequestPendingAfterLoad = false
        if engineIsEnabled {
            if !activationInFlight { isBusy = false }
            return
        }
        monitoringPermissionRequestRecommended = false
        ensureMonitoringEngineEnabled()
    }

    /// The extension is NeManeem's only exact per-app measurement backend, so it
    /// remains enabled independent of whether app blocking is enabled. Background
    /// callers do not bypass a pending first-run permission request.
    func ensureMonitoringEngineEnabled() {
        guard !removalInProgress, hasLoadedPreferences, !activationInFlight, !monitoringPermissionRequestRecommended else { return }
        activationInFlight = true
        isBusy = true
        statusMessage = nil

        extensionController.activate(identifier: AppConstants.filterBundleIdentifier) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.activationInFlight = false
                if self.removalInProgress {
                    Self.logger.notice("Ignoring activation completion because safe removal is in progress")
                    return
                }
                switch result {
                case .success:
                    self.extensionNeedsUserApproval = false
                    self.monitoringPermissionRequestRecommended = false
                    UserDefaults.standard.set(AppConstants.trafficSnapshotSchemaVersion,
                                              forKey: AppConstants.extensionRequestedSchemaDefaultsKey)
                    Self.logger.notice("System Extension activation request completed requestedSchema=\(AppConstants.trafficSnapshotSchemaVersion, privacy: .public)")
                    self.configureEngine(blockingEnabled: self.isEnabled)
                case .failure(let error):
                    let nsError = error as NSError
                    Self.logger.error("System Extension activation failed errorDomain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
                    self.isBusy = false
                    self.engineIsEnabled = false
                    self.monitoringPermissionRequestRecommended = true
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }


    enum SystemExtensionRemovalState {
        case removed
        case requiresReboot
        case notInstalled
        case retryLater
        case failed(String)
    }

    struct RemovalOutcome {
        let filterPreferencesRemoved: Bool
        let filterPreferencesError: String?
        let systemExtension: SystemExtensionRemovalState
    }

    /// User-initiated uninstall preparation. This first removes the active content
    /// filter configuration (which releases monitoring/blocking), then submits the
    /// public System Extension deactivation request. No install/activation retry is
    /// allowed while this process remains alive.
    func prepareMonitoringForRemoval(completion: @escaping (RemovalOutcome) -> Void) {
        guard !removalInProgress else { return }
        let operationID = UUID()
        removalInProgress = true
        removalOperationID = operationID
        isBusy = true
        statusMessage = nil
        monitoringPermissionRequestRecommended = false
        extensionNeedsUserApproval = false
        isDataLimitInternetBlocked = false
        dataLimitBlockLeaseExpiresAt = 0
        isEnabled = false

        manager.loadFromPreferences { [weak self] loadError in
            Task { @MainActor in
                guard let self, self.removalOperationID == operationID else { return }
                if let loadError {
                    self.finishSystemExtensionRemoval(filterRemoved: false,
                                                      filterError: loadError.localizedDescription,
                                                      operationID: operationID,
                                                      completion: completion)
                    return
                }

                let hasSavedFilterConfiguration = self.manager.isEnabled || self.manager.providerConfiguration != nil
                guard hasSavedFilterConfiguration else {
                    self.engineIsEnabled = false
                    self.hasLoadedPreferences = false
                    self.finishSystemExtensionRemoval(filterRemoved: true,
                                                      filterError: nil,
                                                      operationID: operationID,
                                                      completion: completion)
                    return
                }

                self.manager.removeFromPreferences { [weak self] removeError in
                    Task { @MainActor in
                        guard let self, self.removalOperationID == operationID else { return }
                        self.engineIsEnabled = false
                        self.hasLoadedPreferences = false
                        self.finishSystemExtensionRemoval(filterRemoved: removeError == nil,
                                                          filterError: removeError?.localizedDescription,
                                                          operationID: operationID,
                                                          completion: completion)
                    }
                }
            }
        }
    }

    private func finishSystemExtensionRemoval(filterRemoved: Bool,
                                              filterError: String?,
                                              operationID: UUID,
                                              completion: @escaping (RemovalOutcome) -> Void) {
        // Always submit the public deactivation request. If the extension is already
        // absent macOS returns extensionNotFound, which we treat as a clean result.
        // Avoid relying on Host-side schema/default markers: they can be missing even
        // while an older System Extension registration is still present.
        extensionController.deactivate(identifier: AppConstants.filterBundleIdentifier) { [weak self] result in
            Task { @MainActor in
                guard let self, self.removalOperationID == operationID else { return }
                self.isBusy = false
                self.removalInProgress = false
                self.removalOperationID = nil
                switch result {
                case .success(let extensionResult):
                    UserDefaults.standard.removeObject(forKey: AppConstants.extensionActiveSchemaDefaultsKey)
                    UserDefaults.standard.removeObject(forKey: AppConstants.extensionRequestedSchemaDefaultsKey)
                    switch extensionResult {
                    case .completed:
                        completion(RemovalOutcome(filterPreferencesRemoved: filterRemoved,
                                                   filterPreferencesError: filterError,
                                                   systemExtension: .removed))
                    case .willCompleteAfterReboot:
                        completion(RemovalOutcome(filterPreferencesRemoved: filterRemoved,
                                                   filterPreferencesError: filterError,
                                                   systemExtension: .requiresReboot))
                    @unknown default:
                        completion(RemovalOutcome(filterPreferencesRemoved: filterRemoved,
                                                   filterPreferencesError: filterError,
                                                   systemExtension: .requiresReboot))
                    }
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == OSSystemExtensionError.errorDomain &&
                        nsError.code == OSSystemExtensionError.Code.extensionNotFound.rawValue {
                        completion(RemovalOutcome(filterPreferencesRemoved: filterRemoved,
                                                   filterPreferencesError: filterError,
                                                   systemExtension: .notInstalled))
                    } else if nsError.domain == OSSystemExtensionError.errorDomain &&
                                nsError.code == OSSystemExtensionError.Code.requestSuperseded.rawValue {
                        // macOS is still resolving an earlier activation/deactivation
                        // request for this same System Extension. This is transient,
                        // not evidence of a broken extension; preserve user data and
                        // ask the user to retry after the OS finishes the prior work.
                        completion(RemovalOutcome(filterPreferencesRemoved: filterRemoved,
                                                   filterPreferencesError: filterError,
                                                   systemExtension: .retryLater))
                    } else {
                        completion(RemovalOutcome(filterPreferencesRemoved: filterRemoved,
                                                   filterPreferencesError: filterError,
                                                   systemExtension: .failed(error.localizedDescription)))
                    }
                }
            }
        }
    }

    /// Stops waiting for an unresponsive macOS removal operation.  A preference
    /// or extension request that already reached macOS is intentionally not
    /// rolled back; later callbacks are ignored and the UI can safely close.
    func cancelRemovalPreparation() {
        guard removalInProgress else { return }
        removalOperationID = nil
        removalInProgress = false
        isBusy = false
        statusMessage = nil
    }

    /// Enables or disables only rule enforcement. Measurement stays active.
    /// App blocking never becomes enabled merely because the user is being sent
    /// through the separate monitoring-permission setup flow.
    func setEnabled(_ enabled: Bool) {
        statusMessage = nil

        guard hasLoadedPreferences else {
            loadStatus()
            return
        }
        guard engineIsEnabled else {
            if enabled { requestMonitoringPermission() }
            return
        }

        let previous = isEnabled
        isEnabled = enabled
        saveVendorConfiguration(blockingEnabled: enabled) { [weak self] error in
            guard let self else { return }
            if let error {
                self.isEnabled = previous
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func isBlocked(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !Self.isProtectedNeManeemIdentifier(bundleIdentifier) else { return false }
        return blockedBundleIdentifiers.contains(bundleIdentifier)
    }

    func isAllowed(_ bundleIdentifier: String?) -> Bool { !isBlocked(bundleIdentifier) }

    func isProcessBlocked(_ processIdentifier: String?) -> Bool {
        guard let processIdentifier, Self.isBlockableProcessIdentifier(processIdentifier) else { return false }
        return blockedProcessIdentifiers.contains(processIdentifier)
    }

    func isProcessAllowed(_ processIdentifier: String?) -> Bool { !isProcessBlocked(processIdentifier) }

    func setProcessBlockingEnabled(_ enabled: Bool) {
        processBlockingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: processBlockingEnabledDefaultsKey)
        if engineIsEnabled { updateVendorConfiguration() }
    }

    func refreshCompatibilityPolicy() {
        if engineIsEnabled { updateVendorConfiguration() }
    }

    func clearBlockedApps() {
        blockedBundleIdentifiers.removeAll()
        blockedProcessIdentifiers.removeAll()
        processBlockingEnabled = false
        UserDefaults.standard.set([], forKey: blockedDefaultsKey)
        UserDefaults.standard.set([], forKey: blockedProcessesDefaultsKey)
        UserDefaults.standard.set(false, forKey: processBlockingEnabledDefaultsKey)
        if engineIsEnabled { updateVendorConfiguration() }
    }

    func setAllowed(_ allowed: Bool, bundleIdentifier: String?) {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              !Self.isProtectedNeManeemIdentifier(bundleIdentifier) else { return }
        if allowed { blockedBundleIdentifiers.remove(bundleIdentifier) }
        else { blockedBundleIdentifiers.insert(bundleIdentifier) }
        UserDefaults.standard.set(Array(blockedBundleIdentifiers).sorted(), forKey: blockedDefaultsKey)
        if engineIsEnabled { updateVendorConfiguration() }
    }

    func setProcessAllowed(_ allowed: Bool, processIdentifier: String?) {
        guard let processIdentifier, Self.isBlockableProcessIdentifier(processIdentifier) else { return }
        if allowed { blockedProcessIdentifiers.remove(processIdentifier) }
        else { blockedProcessIdentifiers.insert(processIdentifier) }
        UserDefaults.standard.set(Array(blockedProcessIdentifiers).sorted(), forKey: blockedProcessesDefaultsKey)
        if engineIsEnabled { updateVendorConfiguration() }
    }

    private static func isProtectedNeManeemIdentifier(_ identifier: String) -> Bool {
        identifier == AppConstants.appBundleIdentifier ||
        identifier == AppConstants.filterBundleIdentifier ||
        identifier.hasPrefix(AppConstants.appBundleIdentifier + ".")
    }

    private static func isBlockableProcessIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty &&
        !identifier.hasPrefix("__nemaneem.") &&
        !isProtectedNeManeemIdentifier(identifier) &&
        identifier.lowercased() != "unicornprod" &&
        !identifier.lowercased().hasSuffix(".unicornprod")
    }

    /// Emergency whole-internet block used by Data Limit Management. Local/private
    /// network flows remain available; the provider treats unclassified remote
    /// endpoints conservatively as Internet while this guard is active.
    func setDataLimitInternetBlocked(_ blocked: Bool) {
        if blocked,
           UserDefaults.standard.integer(forKey: AppConstants.extensionActiveSchemaDefaultsKey) < AppConstants.trafficSnapshotSchemaVersion {
            // Older providers do not understand shared Host-liveness fail-open safety.
            // Never arm a global Internet block until the new provider is active.
            Self.logger.notice("Data-limit block deferred until fail-open provider generation is active")
            return
        }
        if blocked == isDataLimitInternetBlocked { return }
        // Build 143+: the provider gates both app blocking and Data Limit blocking
        // on the signed Host's shared XPC liveness. No 5-second preference rewrite
        // heartbeat is needed; policy preferences change only when policy changes.
        dataLimitBlockLeaseExpiresAt = 0

        let previous = isDataLimitInternetBlocked
        isDataLimitInternetBlocked = blocked
        statusMessage = nil
        if engineIsEnabled {
            saveVendorConfiguration(blockingEnabled: isEnabled) { [weak self] error in
                guard let self, error != nil else { return }
                self.isDataLimitInternetBlocked = previous
                if !previous { self.dataLimitBlockLeaseExpiresAt = 0 }
            }
        } else if blocked {
            ensureMonitoringEngineEnabled()
        }
    }

    /// Called during normal Host termination. The explicit save is best-effort.
    /// App-specific rules stay saved for the next launch, but the provider also
    /// fails open as soon as the signed Host XPC connection disappears.
    func prepareForHostTermination() {
        guard isDataLimitInternetBlocked else { return }
        isDataLimitInternetBlocked = false
        dataLimitBlockLeaseExpiresAt = 0
        if engineIsEnabled { saveVendorConfiguration(blockingEnabled: isEnabled, completion: nil) }
    }

    private func configureEngine(blockingEnabled: Bool) {
        isBusy = true
        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.finishEngineConfiguration(error: error)
                    return
                }

                let existing = self.manager.providerConfiguration
                let providerMatches = existing?.filterDataProviderBundleIdentifier == AppConstants.filterBundleIdentifier
                let socketsEnabled = existing?.filterSockets ?? false
                let packetsEnabled = existing?.filterPackets ?? false

                // Activating/replacing the System Extension and saving NEFilterManager
                // preferences are two separate macOS network reconfiguration steps.
                // If the content-filter configuration is already valid, keep it as-is
                // and let the newly activated extension attach to the existing config.
                // This avoids an unnecessary second network interruption.
                if self.manager.isEnabled && providerMatches && socketsEnabled && !packetsEnabled {
                    self.isBusy = false
                    self.engineIsEnabled = true
                    self.monitoringPermissionRequestRecommended = false
                    self.statusMessage = nil
                    Self.logger.notice("Filter preferences already valid; skipped saveToPreferences after System Extension activation")
                    return
                }

                Self.logger.notice("Filter preferences require configuration; starting the single necessary saveToPreferences operation")
                self.filterReconfigurationStartedAt = Date()
                let configuration = existing ?? NEFilterProviderConfiguration()
                configuration.filterDataProviderBundleIdentifier = AppConstants.filterBundleIdentifier
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.vendorConfiguration = self.vendorConfiguration(blockingEnabled: blockingEnabled)
                self.manager.providerConfiguration = configuration
                self.manager.localizedDescription = "NeManeem"
                self.manager.grade = .firewall
                self.manager.isEnabled = true
                self.manager.saveToPreferences { [weak self] error in
                    Task { @MainActor in
                        self?.finishEngineConfiguration(error: error)
                    }
                }
            }
        }
    }

    private func finishEngineConfiguration(error: Error?) {
        if let startedAt = filterReconfigurationStartedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            Self.logger.notice("Filter preference reconfiguration callback received after \(elapsed, privacy: .public)s")
            filterReconfigurationStartedAt = nil
        }
        if let error {
            isBusy = false
            engineIsEnabled = false
            monitoringPermissionRequestRecommended = true
            statusMessage = error.localizedDescription
            let nsError = error as NSError
            Self.logger.error("Filter configuration failed errorDomain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            return
        }

        Self.logger.notice("Filter configuration save completed; verifying saved preferences")
        manager.loadFromPreferences { [weak self] verifyError in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                if let verifyError {
                    let nsError = verifyError as NSError
                    self.engineIsEnabled = false
                    self.monitoringPermissionRequestRecommended = true
                    self.statusMessage = verifyError.localizedDescription
                    Self.logger.error("Filter configuration verification failed errorDomain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
                    return
                }

                let configuration = self.manager.providerConfiguration
                let providerMatches = configuration?.filterDataProviderBundleIdentifier == AppConstants.filterBundleIdentifier
                let socketsEnabled = configuration?.filterSockets ?? false
                self.engineIsEnabled = self.manager.isEnabled && providerMatches && socketsEnabled
                self.monitoringPermissionRequestRecommended = !self.engineIsEnabled
                self.statusMessage = nil
                Self.logger.notice("Filter configuration verified enabled=\(self.manager.isEnabled, privacy: .public) providerMatches=\(providerMatches, privacy: .public) socketsEnabled=\(socketsEnabled, privacy: .public)")
            }
        }
    }

    private func updateVendorConfiguration() {
        saveVendorConfiguration(blockingEnabled: isEnabled, completion: nil)
    }

    private func saveVendorConfiguration(blockingEnabled: Bool, completion: ((Error?) -> Void)?) {
        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    completion?(error)
                    return
                }

                let desiredVendor = self.vendorConfiguration(blockingEnabled: blockingEnabled)
                let configuration = self.manager.providerConfiguration ?? NEFilterProviderConfiguration()
                let providerMatches = configuration.filterDataProviderBundleIdentifier == AppConstants.filterBundleIdentifier
                let socketsEnabled = configuration.filterSockets
                let packetsEnabled = configuration.filterPackets
                let existingVendor = configuration.vendorConfiguration ?? [:]

                if self.manager.isEnabled, providerMatches, socketsEnabled, !packetsEnabled,
                   Self.vendorConfiguration(existingVendor, equals: desiredVendor) {
                    self.engineIsEnabled = true
                    self.statusMessage = nil
                    Self.logger.debug("Skipped redundant Network Extension preference save because the effective policy is unchanged")
                    completion?(nil)
                    return
                }

                configuration.filterDataProviderBundleIdentifier = AppConstants.filterBundleIdentifier
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.vendorConfiguration = desiredVendor
                self.manager.providerConfiguration = configuration
                self.manager.localizedDescription = "NeManeem"
                self.manager.grade = .firewall
                // Never disable the filter here: it is also the measurement engine.
                self.manager.isEnabled = true
                let startedAt = Date()
                Self.logger.notice("Network Extension policy changed; saving preferences once")
                self.manager.saveToPreferences { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        let elapsed = Date().timeIntervalSince(startedAt)
                        Self.logger.notice("Network Extension policy save completed after \(elapsed, privacy: .public)s")
                        self.engineIsEnabled = error == nil
                        self.statusMessage = error?.localizedDescription
                        completion?(error)
                    }
                }
            }
        }
    }

    private static func vendorConfiguration(_ lhs: [String: Any], equals rhs: [String: Any]) -> Bool {
        let lhsApps = Set(lhs[AppConstants.blockedAppsConfigurationKey] as? [String] ?? [])
        let rhsApps = Set(rhs[AppConstants.blockedAppsConfigurationKey] as? [String] ?? [])
        let lhsProcesses = Set(lhs[AppConstants.blockedProcessesConfigurationKey] as? [String] ?? [])
        let rhsProcesses = Set(rhs[AppConstants.blockedProcessesConfigurationKey] as? [String] ?? [])
        let lhsBlocking = lhs[AppConstants.blockingEnabledConfigurationKey] as? Bool ?? false
        let rhsBlocking = rhs[AppConstants.blockingEnabledConfigurationKey] as? Bool ?? false
        let lhsProcessBlocking = lhs[AppConstants.processBlockingEnabledConfigurationKey] as? Bool ?? false
        let rhsProcessBlocking = rhs[AppConstants.processBlockingEnabledConfigurationKey] as? Bool ?? false
        let lhsLimitBlock = lhs[AppConstants.dataLimitInternetBlockConfigurationKey] as? Bool ?? false
        let rhsLimitBlock = rhs[AppConstants.dataLimitInternetBlockConfigurationKey] as? Bool ?? false
        let lhsLease = lhs[AppConstants.dataLimitBlockLeaseExpiryConfigurationKey] as? Double ?? 0
        let rhsLease = rhs[AppConstants.dataLimitBlockLeaseExpiryConfigurationKey] as? Double ?? 0
        let lhsSafariGrouping = lhs[AppConstants.safariNetworkServiceGroupingConfigurationKey] as? Bool ?? false
        let rhsSafariGrouping = rhs[AppConstants.safariNetworkServiceGroupingConfigurationKey] as? Bool ?? false
        return lhsApps == rhsApps && lhsProcesses == rhsProcesses && lhsBlocking == rhsBlocking && lhsProcessBlocking == rhsProcessBlocking &&
            lhsLimitBlock == rhsLimitBlock && lhsLease == rhsLease && lhsSafariGrouping == rhsSafariGrouping
    }

    private func vendorConfiguration(blockingEnabled: Bool) -> [String: Any] {
        [
            AppConstants.blockedAppsConfigurationKey: blockedBundleIdentifiers.filter { !Self.isProtectedNeManeemIdentifier($0) }.sorted(),
            AppConstants.blockedProcessesConfigurationKey: blockedProcessIdentifiers.filter { Self.isBlockableProcessIdentifier($0) }.sorted(),
            AppConstants.blockingEnabledConfigurationKey: blockingEnabled,
            AppConstants.processBlockingEnabledConfigurationKey: processBlockingEnabled,
            AppConstants.dataLimitInternetBlockConfigurationKey: isDataLimitInternetBlocked,
            AppConstants.dataLimitBlockLeaseExpiryConfigurationKey: dataLimitBlockLeaseExpiresAt,
            AppConstants.safariNetworkServiceGroupingConfigurationKey: UserDefaults.standard.bool(forKey: AppConstants.safariNetworkServiceGroupingDefaultsKey)
        ]
    }
}

private final class SystemExtensionController: NSObject, OSSystemExtensionRequestDelegate {
    var onNeedsUserApproval: (() -> Void)?
    private let logger = Logger(subsystem: "com.bak2ya.NeManeem", category: "SystemExtensionRequest")

    private enum RequestContext {
        case activation(startedAt: Date, completion: (Result<Void, Error>) -> Void)
        case deactivation(startedAt: Date, completion: (Result<OSSystemExtensionRequest.Result, Error>) -> Void)

        var startedAt: Date {
            switch self {
            case .activation(let startedAt, _), .deactivation(let startedAt, _):
                return startedAt
            }
        }
    }

    /// macOS may finish an older activation after a user immediately starts safe
    /// removal. Keep completion state keyed by the actual request object so one
    /// request can never overwrite or misattribute another request's callback.
    private var contexts: [ObjectIdentifier: RequestContext] = [:]

    func activate(identifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.notice("System Extension activation request submitted")
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        contexts[ObjectIdentifier(request)] = .activation(startedAt: Date(), completion: completion)
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivate(identifier: String, completion: @escaping (Result<OSSystemExtensionRequest.Result, Error>) -> Void) {
        logger.notice("System Extension deactivation request submitted")
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        contexts[ObjectIdentifier(request)] = .deactivation(startedAt: Date(), completion: completion)
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // macOS presents the native approval UI when approval is required.
        logger.notice("System Extension requires native user approval")
        onNeedsUserApproval?()
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let key = ObjectIdentifier(request)
        guard let context = contexts.removeValue(forKey: key) else {
            logger.notice("System Extension completion arrived for an already-finished request")
            return
        }
        let elapsed = Date().timeIntervalSince(context.startedAt)
        logger.notice("System Extension request finished result=\(String(describing: result), privacy: .public) elapsed=\(elapsed, privacy: .public)s")
        switch context {
        case .activation(_, let completion):
            completion(.success(()))
        case .deactivation(_, let completion):
            completion(.success(result))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let key = ObjectIdentifier(request)
        guard let context = contexts.removeValue(forKey: key) else {
            logger.notice("System Extension failure arrived for an already-finished request")
            return
        }
        let elapsed = Date().timeIntervalSince(context.startedAt)
        let nsError = error as NSError
        logger.error("System Extension request failed errorDomain=\(nsError.domain, privacy: .public) code=\(nsError.code) elapsed=\(elapsed, privacy: .public)s")
        switch context {
        case .activation(_, let completion):
            completion(.failure(error))
        case .deactivation(_, let completion):
            completion(.failure(error))
        }
    }
}
