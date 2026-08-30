import AppKit
import Combine
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.bak2ya.NeManeem", category: "Lifecycle")
    private var statusBarController: StatusBarController?
    private var mainWindowController: MainWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let hostRunningKey = "lifecycle.hostRunning"
    private let hasLaunchedKey = "lifecycle.hasLaunchedBefore"
    private let runTokenKey = "lifecycle.runToken"
    private let intentionalRelaunchKey = "lifecycle.intentionalRelaunchPending"
    private let trackingGapPendingKey = "lifecycle.trackingGapPending"
    private let trackingGapDataLimitKey = "lifecycle.trackingGapDataLimitWasEnabled"
    private let suppressTrackingQuitWarningKey = "lifecycle.suppressTrackingQuitWarningOnce"
    private let runToken = UUID().uuidString
    private let monitoringPermissionIntroShownKey = "network.monitoringPermissionIntroShown"
    private var monitoringPermissionPromptScheduled = false
    private var launchStartedAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let defaults = UserDefaults.standard
        let hadPreviousLaunch = defaults.bool(forKey: hasLaunchedKey)
        let priorRunToken = defaults.string(forKey: runTokenKey)
        let legacyRunningMarker = defaults.bool(forKey: hostRunningKey)
        let intentionalRelaunch = defaults.bool(forKey: intentionalRelaunchKey)
        let previousRunWasUnclean = hadPreviousLaunch && (priorRunToken != nil || legacyRunningMarker) && !intentionalRelaunch
        let cleanQuitTrackingGapPending = defaults.bool(forKey: trackingGapPendingKey)
        let cleanQuitHadDataLimit = defaults.bool(forKey: trackingGapDataLimitKey)

        defaults.set(false, forKey: intentionalRelaunchKey)
        defaults.set(false, forKey: trackingGapPendingKey)
        defaults.set(false, forKey: trackingGapDataLimitKey)
        defaults.set(true, forKey: hasLaunchedKey)
        defaults.set(true, forKey: hostRunningKey)
        defaults.set(runToken, forKey: runTokenKey)

        launchStartedAt = Date()
        logger.info("applicationDidFinishLaunching")
        Task { @MainActor in
            let environment = AppEnvironment.shared
            logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s AppEnvironment ready")
            AppearanceController.apply(environment.settings.appearance)
            environment.appTrafficMonitor.setResourceMode(environment.settings.resourceMode)

            // Establish the visible menu-bar surface before starting monitoring or
            // optional network-identity services. If a measurement component has a
            // runtime problem, app launch itself must not become invisible.
            mainWindowController = MainWindowController(environment: environment)
            statusBarController = StatusBarController(environment: environment) { [weak self] mode in
                self?.mainWindowController?.show(mode: mode)
            }
            logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s Status bar UI ready")

            let uncleanTrackingGap = previousRunWasUnclean &&
                (environment.settings.recordingMode != .off || environment.settings.dataLimitEnabled)
            let shouldWarnAboutTrackingGap = cleanQuitTrackingGapPending || uncleanTrackingGap
            let trackingGapHadDataLimit = cleanQuitHadDataLimit ||
                (previousRunWasUnclean && environment.settings.dataLimitEnabled)

            if previousRunWasUnclean || shouldWarnAboutTrackingGap {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    // Keep launch warnings serialized so two native modals never stack.
                    if previousRunWasUnclean {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = L10n.text("previousRunAbnormalTitle", language: environment.settings.language)
                        alert.informativeText = L10n.text("previousRunAbnormalBody", language: environment.settings.language)
                        alert.addButton(withTitle: L10n.text("ok", language: environment.settings.language))
                        alert.runModal()
                    }

                    if shouldWarnAboutTrackingGap {
                        self.presentTrackingGapWarning(environment: environment,
                                                       dataLimitWasEnabled: trackingGapHadDataLimit)
                    }
                }
            }

            // Observe the permission state before loadStatus(). On a clean install
            // FirewallController intentionally waits for a visible user action instead
            // of racing macOS approval UI during launch.
            environment.firewallController.$monitoringPermissionRequestRecommended
                .removeDuplicates()
                .filter { $0 }
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.scheduleMonitoringPermissionIntro(environment: AppEnvironment.shared)
                    }
                }
                .store(in: &cancellables)

            environment.settings.$refreshIntervalSeconds
                .dropFirst()
                .sink { interval in
                    environment.interfaceMonitor.setRefreshInterval(SettingsStore.normalizeInterval(interval))
                }
                .store(in: &cancellables)

            // Keep the exact app-traffic sampling engine aligned with the effective
            // Status Window hierarchy: Menu Bar -> Popover -> Monitor Window.
            Publishers.CombineLatest4(
                environment.settings.$refreshIntervalSeconds,
                environment.settings.$popoverRefreshIntervalSeconds,
                environment.settings.$popoverUseMenuBarRefresh,
                environment.settings.$monitorRefreshIntervalSeconds
            )
            .combineLatest(
                Publishers.CombineLatest(
                    environment.settings.$monitorUsePopoverSettings,
                    environment.settings.$monitorUseMenuBarRefresh
                )
            )
            .sink { combined in
                let (values, monitorChoices) = combined
                let (usePopover, monitorUsesMenu) = monitorChoices
                let (menu, popoverStored, useMenu, monitorStored) = values
                let popover = useMenu ? menu : popoverStored
                environment.appTrafficMonitor.setConfiguredIntervals(
                    menuBar: menu,
                    popover: popover,
                    monitor: usePopover ? popover : (monitorUsesMenu ? menu : monitorStored)
                )
            }
            .store(in: &cancellables)

            // A temporary XPC outage can happen while macOS is attaching or
            // restarting the already-enabled Network Extension. Do not respond by
            // submitting another activation/save request: that can cause a second
            // network reconfiguration and make the interruption feel much longer.
            // The traffic monitor keeps retrying XPC; this path only re-reads status.
            environment.appTrafficMonitor.$hasPersistentConnectionError
                .removeDuplicates()
                .filter { $0 }
                .sink { _ in environment.firewallController.refreshEngineStatusWithoutReconfiguration() }
                .store(in: &cancellables)

            environment.settings.$appearance
                .dropFirst()
                .sink { AppearanceController.apply($0) }
                .store(in: &cancellables)

            environment.settings.$resourceMode
                .removeDuplicates()
                .sink { mode in
                    environment.appTrafficMonitor.setResourceMode(mode)
                    if mode == .austerity || mode == .saver {
                        environment.appTrafficMonitor.clearTemporaryCaches()
                        environment.usageRecorder.clearTemporaryCaches()
                    }
                }
                .store(in: &cancellables)

            logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s visible launch setup completed")

            // Build 50: visible UI first, persistent history/catalog/network services second.
            // The user can click the menu-bar item immediately; views show their normal
            // preparing state until these deferred tasks finish.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s deferred startup begun")

                // Start the light live path first. Persistent history may be large, but
                // it must never delay the menu-bar speed source or permission/status
                // discovery once the visible surface already exists.
                environment.interfaceMonitor.start(refreshInterval: environment.settings.refreshIntervalSeconds)
                // Rehydrate an already-authorized SSID identity after every launch
                // without prompting. This keeps the user-facing current connection
                // on the real Wi-Fi name instead of a generic interface label.
                environment.interfaceMonitor.refreshWiFiIdentityAuthorizationStatus()
                environment.firewallController.loadStatus()
                self.logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s network monitoring startup requested")

                await environment.usageRecorder.loadPersistedStateAfterLaunch()
                self.logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s usage history loaded")
                environment.appTrafficMonitor.hydrateObservedCatalogAfterLaunch()
                self.logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s observed catalog loaded")
                environment.usageRecorder.activateRuntimeAfterLaunch()
                self.logger.info("Launch +\(self.elapsedLaunchSeconds(), privacy: .public)s deferred startup completed")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.logger.info("Host heartbeat +2s")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                self.logger.info("Host heartbeat +10s")
            }
        }
    }

    @MainActor
    private func presentTrackingGapWarning(environment: AppEnvironment, dataLimitWasEnabled: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("trackingGapWarningTitle", language: environment.settings.language)
        alert.informativeText = L10n.text(dataLimitWasEnabled ? "trackingGapWarningLimitBody" : "trackingGapWarningBody",
                                         language: environment.settings.language)
        // NSAlert lays the first button out as the default action on the right.
        // Add OK first so the corrective action stays on the left as requested.
        alert.addButton(withTitle: L10n.text("ok", language: environment.settings.language))
        if dataLimitWasEnabled {
            alert.addButton(withTitle: L10n.text("reapplyCurrentValue", language: environment.settings.language))
        }
        let response = alert.runModal()
        if dataLimitWasEnabled && response == .alertSecondButtonReturn {
            environment.requestSettingsSection?("dataLimit-current")
        }
    }

    private func elapsedLaunchSeconds() -> Double {
        Date().timeIntervalSince(launchStartedAt)
    }

    @MainActor
    private func scheduleMonitoringPermissionIntro(environment: AppEnvironment) {
        guard !UserDefaults.standard.bool(forKey: monitoringPermissionIntroShownKey),
              !monitoringPermissionPromptScheduled else { return }
        monitoringPermissionPromptScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self else { return }
            self.presentMonitoringPermissionIntro(environment: environment)
        }
    }

    @MainActor
    private func presentMonitoringPermissionIntro(environment: AppEnvironment) {
        guard environment.firewallController.monitoringPermissionRequestRecommended else {
            monitoringPermissionPromptScheduled = false
            return
        }
        // Do not stack this alert on top of the abnormal-termination notice or any
        // other native modal. Retry shortly after that modal has been dismissed.
        if NSApp.modalWindow != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.presentMonitoringPermissionIntro(environment: environment)
            }
            return
        }

        monitoringPermissionPromptScheduled = false
        UserDefaults.standard.set(true, forKey: monitoringPermissionIntroShownKey)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("monitoringPermissionTitle", language: environment.settings.language)
        alert.informativeText = L10n.text("monitoringPermissionBody", language: environment.settings.language)
        alert.addButton(withTitle: L10n.text("requestNetworkPermission", language: environment.settings.language))
        alert.addButton(withTitle: L10n.text("later", language: environment.settings.language))
        if alert.runModal() == .alertFirstButtonReturn {
            environment.firewallController.requestMonitoringPermission()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let defaults = UserDefaults.standard

        // Clean-removal and the app's own deliberate relaunch must not be stopped by
        // the normal usage-gap warning. The relaunch path sets a one-shot marker
        // consumed only by the process that is about to terminate.
        if SettingsTransferService.persistentDataClearedForRemoval {
            return .terminateNow
        }
        if defaults.bool(forKey: suppressTrackingQuitWarningKey) {
            defaults.set(false, forKey: suppressTrackingQuitWarningKey)
            return .terminateNow
        }

        let recordingIsActive = (defaults.string(forKey: "history.recordingMode") ?? "off") != "off"
        let dataLimitIsActive = defaults.bool(forKey: "data.limitEnabled")
        guard recordingIsActive || dataLimitIsActive else { return .terminateNow }

        let language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("activeTrackingQuitTitle", language: language)
        alert.informativeText = L10n.text("activeTrackingQuitBody", language: language)
        alert.addButton(withTitle: L10n.text("quitAnyway", language: language))
        alert.addButton(withTitle: L10n.text("cancel", language: language))

        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        defaults.set(true, forKey: trackingGapPendingKey)
        defaults.set(dataLimitIsActive, forKey: trackingGapDataLimitKey)
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.notice("applicationWillTerminate")
        // A successful clean-removal data wipe intentionally leaves the app's
        // persistent defaults domain empty. Do not recreate lifecycle marker keys
        // while terminating that same process.
        if !SettingsTransferService.persistentDataClearedForRemoval {
            let defaults = UserDefaults.standard
            if defaults.string(forKey: runTokenKey) == runToken {
                defaults.removeObject(forKey: runTokenKey)
                defaults.set(false, forKey: hostRunningKey)
            }
        }
        Task { @MainActor in
            AppEnvironment.shared.firewallController.prepareForHostTermination()
            AppEnvironment.shared.interfaceMonitor.stop()
            AppEnvironment.shared.appTrafficMonitor.setDemand(.popover, active: false)
            AppEnvironment.shared.appTrafficMonitor.setDemand(.monitorWindow, active: false)
        }
    }
}
