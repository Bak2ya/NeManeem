import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
private final class PopoverPreviewAnchorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let logger = Logger(subsystem: "com.bak2ya.NeManeem", category: "StatusBar")
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let statusView: StatusItemView
    private let popover = NSPopover()
    private let previewPopover = NSPopover()
    private var previewAnchorPanel: PopoverPreviewAnchorPanel?
    private let openMainWindow: (MainWindowMode) -> Void
    private var cancellables = Set<AnyCancellable>()
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
        statusView.onRightClick = { [weak self] event in self?.showQuickLaunchMenu(with: event) }
        environment.requestPopoverPreview = { [weak self] visible in
            self?.setPopoverPreview(visible)
        }
        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(statusItemPrimaryAction(_:))
            button.setAccessibilityLabel("NeManeem")
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

        // Settings preview uses a second *native* NSPopover so its arrow, material,
        // shadow and corner treatment always match the running macOS release. The
        // tiny nonactivating anchor panel exists only to provide a stable screen
        // attachment point beside Settings; it never becomes user-visible or key.
        previewPopover.behavior = .applicationDefined
        previewPopover.animates = false

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
                guard let self, self.popover.isShown else { return }
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

    @objc private func statusItemPrimaryAction(_ sender: Any?) {
        togglePopover()
    }

    private func togglePopover() {
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

    private func showQuickLaunchMenu(with event: NSEvent) {
        if popover.isShown { popover.performClose(nil) }
        let settings = environment.settings
        let t: (String) -> String = { L10n.text($0, language: settings.language) }
        let menu = NSMenu()
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

        NSMenu.popUpContextMenu(menu, with: event, for: statusView)
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
        environment.popoverPreviewVisible = visible
        if visible {
            showNativePopoverPreview()
        } else {
            previewPopover.performClose(nil)
            previewPopover.contentViewController = nil
            previewAnchorPanel?.orderOut(nil)
            previewAnchorPanel = nil
            environment.appTrafficMonitor.setDemand(.popover, active: popover.isShown && environment.settings.resourceMode != .austerity)
        }
    }

    private func showNativePopoverPreview() {
        let columns = activeStatusColumns(environment.settings.popoverColumns, appBlockingEnabled: environment.firewallController.isEnabled)
        let width = statusWindowRecommendedWidth(columns: columns,
                                                 processMode: environment.settings.popoverProcessDisplay,
                                                 unitMode: environment.settings.popoverUnitMode,
                                                 directionDisplay: environment.settings.popoverDirectionDisplay,
                                                 scale: environment.settings.popoverScale.factor,
                                                 language: environment.settings.language)

        let settingsWindow = NSApp.keyWindow ?? NSApp.windows.first(where: {
            $0.isVisible && $0.level == .normal && $0.contentViewController != nil
        })
        guard let settingsWindow else { return }

        let anchor = previewAnchorPanel ?? PopoverPreviewAnchorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        anchor.level = .floating
        anchor.hasShadow = false
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.alphaValue = 0.01
        anchor.ignoresMouseEvents = true
        anchor.hidesOnDeactivate = false
        anchor.collectionBehavior = [.transient, .moveToActiveSpace]
        if anchor.contentView == nil {
            anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        }

        positionPreviewAnchor(anchor, beside: settingsWindow, previewWidth: width)
        previewAnchorPanel = anchor
        anchor.orderFrontRegardless()

        previewPopover.performClose(nil)
        previewPopover.contentViewController = NSHostingController(rootView:
            PopoverView(openMainWindow: { [weak self] mode in self?.openMainWindow(mode) })
                .allowsHitTesting(false)
        )
        guard let anchorView = anchor.contentView else { return }
        previewPopover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

        // The preview is visual-only. Keep the Settings window as the keyboard target.
        settingsWindow.makeKeyAndOrderFront(nil)
        environment.appTrafficMonitor.setDemand(.popover, active: environment.settings.resourceMode != .austerity)
    }

    private func positionPreviewAnchor(_ anchor: NSPanel, beside settingsWindow: NSWindow, previewWidth: CGFloat) {
        let visible = settingsWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? settingsWindow.frame
        let gap: CGFloat = 12
        let margin: CGFloat = 8

        let leftCenterX = settingsWindow.frame.minX - gap - previewWidth / 2
        let rightCenterX = settingsWindow.frame.maxX + gap + previewWidth / 2
        let leftFits = leftCenterX - previewWidth / 2 >= visible.minX + margin
        let centerX = leftFits ? leftCenterX : min(rightCenterX, visible.maxX - margin - previewWidth / 2)
        let anchorY = min(settingsWindow.frame.maxY - 8, visible.maxY - margin)

        anchor.setFrame(NSRect(x: centerX - 0.5, y: anchorY, width: 1, height: 1), display: false)
    }

    func popoverWillShow(_ notification: Notification) {
        popoverReleaseWorkItem?.cancel()
        popoverReleaseWorkItem = nil
        environment.appTrafficMonitor.setDemand(.popover, active: environment.settings.resourceMode != .austerity)
    }

    func popoverDidClose(_ notification: Notification) {
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
