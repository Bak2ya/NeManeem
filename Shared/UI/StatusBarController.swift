import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let logger = Logger(subsystem: "com.bak2ya.NeManeem", category: "StatusBar")
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let statusView: StatusItemView
    private let popover = NSPopover()
    private let openMainWindow: (MainWindowMode) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var previewOwned = false
    private var previewRequestGeneration = 0
    private var popoverReleaseWorkItem: DispatchWorkItem?
    private var pendingMainWindowMode: MainWindowMode?
    private var latestInterfaceSnapshot = NetworkSnapshot()
    private var latestAppUsages: [AppNetworkUsage] = []

    init(environment: AppEnvironment, openMainWindow: @escaping (MainWindowMode) -> Void) {
        self.environment = environment
        self.openMainWindow = openMainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusView = StatusItemView(frame: NSRect(x: 0, y: 0, width: 46, height: NSStatusBar.system.thickness))
        super.init()

        statusView.settings = environment.settings
        latestInterfaceSnapshot = environment.interfaceMonitor.snapshot
        latestAppUsages = environment.appTrafficMonitor.usages
        statusView.snapshot = scopedMenuBarSnapshot()
        refreshDataLimitSnapshot()
        statusView.onClick = { [weak self] in self?.togglePopover() }
        statusView.onRightClick = { [weak self] in self?.showQuickLaunchMenu() }
        environment.requestPopoverPreview = { [weak self] visible in
            self?.setPopoverPreview(visible)
        }
        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            statusView.frame = button.bounds
            statusView.autoresizingMask = [.width, .height]
            button.addSubview(statusView)
        }
        updateStatusItemLength()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.logger.info("Status item attached=\(self.statusView.window != nil, privacy: .public) length=\(Double(self.statusItem.length), privacy: .public)")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        environment.interfaceMonitor.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestInterfaceSnapshot = snapshot
                self.refreshMenuBarSnapshot()
            }
            .store(in: &cancellables)

        environment.appTrafficMonitor.$usages
            .sink { [weak self] usages in
                guard let self else { return }
                self.latestAppUsages = usages
                if self.environment.settings.effectiveMenuBarTrafficScope == .internetOnly {
                    self.refreshMenuBarSnapshot()
                }
            }
            .store(in: &cancellables)

        environment.settings.$menuBarTrafficScope
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateMenuBarTrafficDemand()
                self.refreshMenuBarSnapshot()
            }
            .store(in: &cancellables)

        environment.settings.$separateLocalTraffic
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateMenuBarTrafficDemand()
                self.refreshMenuBarSnapshot()
            }
            .store(in: &cancellables)

        environment.settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.statusView.settings = self.environment.settings
                    self.updateStatusItemLength()
                }
            }
            .store(in: &cancellables)

        environment.usageRecorder.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshDataLimitSnapshot()
                }
            }
            .store(in: &cancellables)

        environment.settings.$resourceMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.resourceModeDidChange(mode)
            }
            .store(in: &cancellables)

        updateMenuBarTrafficDemand()
        refreshMenuBarSnapshot()

        // NSPopover.behavior = .transient handles normal outside clicks inside
        // the active app. A menu-bar utility can otherwise remain non-active, so
        // also close the visible popover when NeManeem loses application focus.
        // This uses AppKit lifecycle notifications instead of a global mouse hook.
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.popover.isShown, !self.previewOwned else { return }
                self.popover.performClose(nil)
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarTrafficDemand() {
        environment.appTrafficMonitor.setDemand(
            .menuBarInternet,
            active: environment.settings.effectiveMenuBarTrafficScope == .internetOnly
        )
    }

    private func refreshMenuBarSnapshot() {
        statusView.snapshot = scopedMenuBarSnapshot()
    }

    private func refreshDataLimitSnapshot() {
        let total = environment.usageRecorder.currentCycleTotal
        statusView.dataLimitUsedBytes = total.download &+ total.upload
        updateStatusItemLength()
    }

    private func scopedMenuBarSnapshot() -> NetworkSnapshot {
        guard environment.settings.effectiveMenuBarTrafficScope == .internetOnly else {
            return latestInterfaceSnapshot
        }

        var scoped = latestInterfaceSnapshot
        scoped.downloadBytesPerSecond = latestAppUsages.reduce(UInt64(0)) { partial, usage in
            partial &+ usage.internetDownloadBytesPerSecond
        }
        scoped.uploadBytesPerSecond = latestAppUsages.reduce(UInt64(0)) { partial, usage in
            partial &+ usage.internetUploadBytesPerSecond
        }
        return scoped
    }

    private func updateStatusItemLength() {
        statusView.updateGeometry()
        statusItem.length = statusView.intrinsicContentSize.width
        if let button = statusItem.button {
            statusView.frame = button.bounds
        }
    }

    private func togglePopover() {
        // A user click ends Settings-preview ownership. If it closes a preview,
        // the settings toggle follows the actual visible state automatically.
        previewRequestGeneration += 1
        if previewOwned { environment.popoverPreviewVisible = false }
        previewOwned = false
        popover.behavior = .transient
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard statusView.window != nil else { return }
        ensurePopoverContent()
        // Make the accessory app active while the transient popover is visible so
        // standard AppKit outside-click / app-switch dismissal works reliably.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
        statusView.isPopoverShown = true
    }

    private func ensurePopoverContent() {
        guard popover.contentViewController == nil else { return }
        let openWindow: (MainWindowMode) -> Void = { [weak self] mode in
            guard let self else { return }
            self.environment.requestedPresentationScreenFrame = self.statusView.window?.screen?.visibleFrame
            // Do not build a heavy settings/monitor hierarchy while the popover's
            // SwiftUI/AppKit tree is still alive. Instruments showed that overlap
            // contributes directly to the 200+ MB presentation spike. Close first;
            // popoverDidClose releases its content and opens the requested window on
            // the following run-loop turn.
            if self.popover.isShown {
                self.pendingMainWindowMode = mode
                self.popover.performClose(nil)
            } else {
                self.openMainWindow(mode)
            }
        }
        if environment.settings.resourceMode == .austerity {
            // Do not instantiate the full traffic-list view tree at all in extreme
            // saver mode. The lightweight root avoids allocating its app-list state,
            // rate baselines and grouping machinery merely to show the paused message.
            popover.contentViewController = NSHostingController(rootView: AusterityPopoverView(openMainWindow: openWindow))
        } else {
            popover.contentViewController = NSHostingController(rootView: PopoverView(openMainWindow: openWindow))
        }
    }

    private func showQuickLaunchMenu() {
        if popover.isShown { popover.performClose(nil) }
        let settings = environment.settings
        let t: (String) -> String = { L10n.text($0, language: settings.language) }
        let menu = NSMenu()
        let heading = NSMenuItem(title: t("quickMode"), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let matchedProfile = settings.matchingProfile
        for mode in ResourceMode.allCases {
            let item = NSMenuItem(title: t("resourceMode.\(mode.rawValue)"), action: #selector(selectResourceMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            if matchedProfile == nil && settings.resourceMode == mode { item.state = .on }
            menu.addItem(item)
        }

        let quickProfiles = settings.profiles.filter(\.showInQuickLaunch)
        if !quickProfiles.isEmpty {
            menu.addItem(.separator())
            for profile in quickProfiles {
                let item = NSMenuItem(title: "\(t("profilePrefix")): \(profile.name)", action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                if matchedProfile?.id == profile.id { item.state = .on }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: t("settingsStats"), action: #selector(openSettingsFromMenu(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: t("quit"), action: #selector(quitFromMenu(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: statusView.bounds.minY), in: statusView)
    }

    @objc private func selectResourceMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ResourceMode(rawValue: raw) else { return }
        environment.settings.resourceMode = mode
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        environment.settings.applyProfile(id: id)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        environment.requestedPresentationScreenFrame = statusView.window?.screen?.visibleFrame
        openMainWindow(.standard)
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func setPopoverPreview(_ visible: Bool) {
        previewRequestGeneration += 1
        let generation = previewRequestGeneration

        if visible {
            environment.popoverPreviewVisible = true
            showPreviewWhenAnchorIsReady(generation: generation, attempt: 0)
        } else if previewOwned {
            previewOwned = false
            popover.performClose(nil)
            popover.behavior = .transient
            environment.popoverPreviewVisible = false
        } else {
            environment.popoverPreviewVisible = false
        }
    }

    private func showPreviewWhenAnchorIsReady(generation: Int, attempt: Int) {
        guard generation == previewRequestGeneration else { return }
        // If the user already had the live popover open, Settings must not adopt
        // ownership of it. The settings page may use it as the live preview, but
        // leaving the page must not close a window the user opened independently.
        if popover.isShown {
            previewOwned = false
            environment.popoverPreviewVisible = true
            return
        }

        guard statusView.window != nil else {
            guard attempt < 6 else {
                environment.popoverPreviewVisible = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.showPreviewWhenAnchorIsReady(generation: generation, attempt: attempt + 1)
            }
            return
        }

        // Defer one run-loop turn after the menu-bar view has a window. This keeps
        // AppKit from calculating the preview against a stale status-item frame.
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.previewRequestGeneration, !self.popover.isShown else { return }
            self.previewOwned = true
            self.popover.behavior = .applicationDefined
            self.showPopover()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        popoverReleaseWorkItem?.cancel()
        popoverReleaseWorkItem = nil
        environment.appTrafficMonitor.setDemand(.popover, active: environment.settings.resourceMode != .austerity)
    }

    func popoverDidClose(_ notification: Notification) {
        let wasPreview = previewOwned
        previewOwned = false
        if wasPreview { environment.popoverPreviewVisible = false }
        popover.behavior = .transient
        statusView.isPopoverShown = false

        if let pendingMode = pendingMainWindowMode {
            pendingMainWindowMode = nil
            popoverReleaseWorkItem?.cancel()
            popoverReleaseWorkItem = nil
            environment.appTrafficMonitor.setDemand(.popover, active: false)
            // Explicitly tear down even in Performance mode for this transition: the
            // user is leaving the popover, and keeping both view trees alive only
            // increases peak memory while Settings/Monitor is being constructed.
            popover.contentViewController = nil
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.openMainWindow(pendingMode)
            }
            return
        }

        // Keep the live source warm for the user's chosen grace period. This is
        // not a stale-value cache: Network Extension polling continues during the
        // grace period, so reopening the popover can immediately show a current
        // list. A zero-second choice stops the popover demand immediately.
        popoverReleaseWorkItem?.cancel()
        let delay = SettingsStore.normalizeClosedDataRetention(environment.settings.popoverClosedDataRetentionSeconds)
        let effectiveDelay: Double
        switch environment.settings.resourceMode {
        case .austerity: effectiveDelay = 0
        case .saver: effectiveDelay = min(delay, 1)
        case .balanced: effectiveDelay = delay
        case .performance: effectiveDelay = max(delay, 10)
        }
        guard effectiveDelay > 0 else {
            environment.appTrafficMonitor.setDemand(.popover, active: false)
            releasePopoverContentIfAppropriate()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.popover.isShown else { return }
                self.environment.appTrafficMonitor.setDemand(.popover, active: false)
                self.releasePopoverContentIfAppropriate()
                self.popoverReleaseWorkItem = nil
            }
        }
        popoverReleaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: work)
    }

    private func resourceModeDidChange(_ mode: ResourceMode) {
        guard !popover.isShown else { return }
        // A hidden popover must not keep a long grace-period timer from a previous
        // heavier mode. Balanced/Saver/Austerity can rebuild this small SwiftUI tree
        // on demand; Performance intentionally keeps it warm.
        guard mode != .performance else { return }
        popoverReleaseWorkItem?.cancel()
        popoverReleaseWorkItem = nil
        environment.appTrafficMonitor.setDemand(.popover, active: false)
        popover.contentViewController = nil
    }

    private func releasePopoverContentIfAppropriate() {
        guard !popover.isShown else { return }
        if environment.settings.resourceMode != .performance {
            popover.contentViewController = nil
        }
    }
}
