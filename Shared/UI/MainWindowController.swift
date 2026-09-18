import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

private enum SettingsWindowLayoutMetrics {
    // One common canvas width is shared by every settings page. Individual pages
    // must adapt inside this width instead of pushing the NSWindow wider. This is
    // especially important for the Width Fixed mode, which previously broke when
    // moving between pages with different intrinsic minimum widths.
    static let preferredWidth: CGFloat = 820
    static let preferredHeight: CGFloat = 560
    static let minimumWidth: CGFloat = 780
    static let minimumHeight: CGFloat = 480

    static let accessibilityPreferredWidth: CGFloat = 920
    static let accessibilityPreferredHeight: CGFloat = 640
    static let accessibilityMinimumWidth: CGFloat = 860
    static let accessibilityMinimumHeight: CGFloat = 540
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let monitorFrameAutosaveName = "NeManeemMonitorWindowFrameCompactV2"
    private let environment: AppEnvironment
    private var settingsWindow: NSWindow?
    private var monitorWindow: NSWindow?
    private var monitorPreviewOwned = false
    private var monitorLastRecommendedWidth: CGFloat?
    private var settingsUsesLargeAccessibilityText = false
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        environment.requestWindowMode = { [weak self] mode in self?.show(mode: mode) }
        environment.requestSettingsSection = { [weak self] destination in
            self?.showSettings(destination: destination)
        }
        environment.requestMonitorPreview = { [weak self] visible in
            self?.setMonitorPreview(visible)
        }
        environment.requestResetSettingsWindowSize = { [weak self] in
            self?.resetSettingsWindowSize()
        }
        environment.requestResetMonitorWindowSize = { [weak self] in
            self?.resetMonitorWindowSize()
        }
        environment.requestSettingsAccessibilityLayout = { [weak self] largeText in
            guard let self else { return }
            self.settingsUsesLargeAccessibilityText = largeText
            self.applySettingsWindowSizing()
        }

        environment.settings.$settingsWindowSizeMode
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applySettingsWindowSizing() }
            }
            .store(in: &cancellables)

        environment.settings.$alwaysOnTopMonitor
            .sink { [weak self] enabled in
                self?.monitorWindow?.level = enabled ? .floating : .normal
            }
            .store(in: &cancellables)

        environment.settings.$resourceMode
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.releaseHiddenWindowsIfAppropriate()
            }
            .store(in: &cancellables)

        // Status-window width follows the content-driven minimum while the user
        // keeps the window compact. A window the user deliberately enlarged is
        // preserved, while larger text or more columns can still expand the minimum.
        environment.settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateMonitorMinimumWidth() }
            }
            .store(in: &cancellables)
    }

    func show(mode: MainWindowMode) {
        switch mode {
        case .standard: showSettings(destination: nil)
        case .monitor: showMonitor(preview: false)
        }
    }

    private func showSettings(destination: String?) {
        let isNewPresentation = settingsWindow?.isVisible != true
        // Normal Settings presentation starts at General. Explicit shortcuts
        // (for example, Troubleshooting) must keep their destination even when
        // the Settings window is currently closed.
        if let destination {
            environment.requestedSettingsDestination = destination
        } else if isNewPresentation {
            environment.requestedSettingsDestination = MainSection.general.rawValue
        }
        let window = settingsWindow ?? makeSettingsWindow()
        applySettingsWindowSizing()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMonitor(preview: Bool) {
        let alreadyVisible = monitorWindow?.isVisible == true
        // Capture this before NSWindow registers its autosave name. Creating a
        // new window can otherwise make an empty first-run frame look restored
        // and skip the intentional non-overlapping initial placement.
        let hadSavedMonitorFrame = hasValidSavedMonitorFrame()
        let presentationAnchor = monitorPresentationAnchorFrame()
        let window = monitorWindow ?? makeMonitorWindow()
        if !alreadyVisible {
            placeNewMonitorWindowIfNeeded(window,
                                           avoiding: presentationAnchor,
                                           hasSavedFrame: hadSavedMonitorFrame)
        }
        if preview {
            // A settings preview may reuse an already-open monitor window, but it
            // must not claim ownership and close the user's live window on exit.
            monitorPreviewOwned = !alreadyVisible
            environment.monitorPreviewVisible = true
        } else {
            monitorPreviewOwned = false
            environment.monitorPreviewVisible = false
        }
        window.level = environment.settings.alwaysOnTopMonitor ? .floating : .normal
        environment.appTrafficMonitor.setDemand(.monitorWindow, active: true)
        if preview && monitorPreviewOwned {
            // Settings preview must not steal keyboard focus from the settings window.
            window.orderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setMonitorPreview(_ visible: Bool) {
        if visible {
            environment.monitorPreviewVisible = true
            showMonitor(preview: true)
        } else if monitorPreviewOwned {
            monitorPreviewOwned = false
            let hiddenWindow = monitorWindow
            hiddenWindow?.orderOut(nil)
            environment.appTrafficMonitor.setDemand(.monitorWindow, active: false)
            environment.monitorPreviewVisible = false
            releaseMonitorWindowIfNeeded(hiddenWindow)
        } else {
            environment.monitorPreviewVisible = false
        }
    }

    private func makeSettingsWindow() -> NSWindow {
        let controller = NSHostingController(rootView: MainWindowView())
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "NeManeem - Network Manager"
        // Keep the native window identity for macOS/window management, while the
        // visible settings UI uses the floating sidebar and begins directly with
        // content. No duplicate app/page title is drawn inside the detail column.
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        // Settings is a utility panel; avoiding an extra window animation prevents
        // a short-lived duplicate backing surface during first presentation.
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = true
        window.minSize = NSSize(width: SettingsWindowLayoutMetrics.minimumWidth,
                                height: SettingsWindowLayoutMetrics.minimumHeight)
        window.setContentSize(NSSize(width: SettingsWindowLayoutMetrics.preferredWidth,
                                     height: SettingsWindowLayoutMetrics.preferredHeight))
        window.setFrameAutosaveName("NeManeemSettingsWindowFrame")
        positionWindowForCurrentContext(window)
        window.delegate = self
        settingsWindow = window
        applySettingsWindowSizing()
        return window
    }

    private func applySettingsWindowSizing() {
        guard let window = settingsWindow else { return }
        let mode = environment.settings.settingsWindowSizeMode
        // Accessibility text should enlarge the controls and the useful canvas
        // together. Fixed-window preferences remain respected at normal text size,
        // but accessibility takes precedence over a too-small fixed canvas.
        let preferredWidth: CGFloat = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityPreferredWidth
            : SettingsWindowLayoutMetrics.preferredWidth
        let preferredHeight: CGFloat = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityPreferredHeight
            : SettingsWindowLayoutMetrics.preferredHeight
        let minimumWidth: CGFloat = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityMinimumWidth
            : SettingsWindowLayoutMetrics.minimumWidth
        let minimumHeight: CGFloat = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityMinimumHeight
            : SettingsWindowLayoutMetrics.minimumHeight
        let currentHeight = max(minimumHeight, window.contentView?.bounds.height ?? preferredHeight)
        switch mode {
        case .free:
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: minimumWidth, height: minimumHeight)
            window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
            let currentWidth = window.contentView?.bounds.width ?? preferredWidth
            if currentWidth < minimumWidth || (settingsUsesLargeAccessibilityText && currentWidth < preferredWidth) {
                window.setContentSize(NSSize(width: settingsUsesLargeAccessibilityText ? preferredWidth : minimumWidth,
                                             height: max(currentHeight, settingsUsesLargeAccessibilityText ? preferredHeight : minimumHeight)))
            }
        case .widthFixed:
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: preferredWidth, height: minimumHeight)
            window.contentMaxSize = NSSize(width: preferredWidth, height: 10_000)
            window.setContentSize(NSSize(width: preferredWidth, height: currentHeight))
        case .sizeFixed:
            window.styleMask.remove(.resizable)
            window.contentMinSize = NSSize(width: preferredWidth, height: preferredHeight)
            window.contentMaxSize = NSSize(width: preferredWidth, height: preferredHeight)
            window.setContentSize(NSSize(width: preferredWidth, height: preferredHeight))
        }
    }

    private func resetSettingsWindowSize() {
        // NSWindow frame autosave includes both size and position. A settings reset
        // should therefore clear the persisted frame as well as resize the currently
        // open window, so the next launch does not restore the pre-reset geometry.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame NeManeemSettingsWindowFrame")
        guard let window = settingsWindow else { return }
        let width = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityPreferredWidth
            : SettingsWindowLayoutMetrics.preferredWidth
        let height = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityPreferredHeight
            : SettingsWindowLayoutMetrics.preferredHeight
        window.setContentSize(NSSize(width: width, height: height))
        applySettingsWindowSizing()
    }

    private func resetMonitorWindowSize() {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame NeManeemMonitorWindowFrameCompactV2")
        guard let window = monitorWindow else { return }
        let width = statusWindowRecommendedWidth(columns: StatusColumn.defaultColumns,
                                                 processMode: .iconAndName,
                                                 unitMode: .bytesPerSecond,
                                                 directionDisplay: .words,
                                                 scale: PopoverScale.standard.factor,
                                                 language: environment.settings.language)
        monitorLastRecommendedWidth = width
        window.contentMinSize = NSSize(width: width, height: 260)
        window.setContentSize(NSSize(width: max(width, 320), height: 360))
        center(window, on: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
    }

    private func positionWindowForCurrentContext(_ window: NSWindow) {
        let requested = environment.requestedPresentationScreenFrame
        environment.requestedPresentationScreenFrame = nil
        let fallback = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        center(window, on: requested ?? fallback)
    }

    private func center(_ window: NSWindow, on visibleFrame: NSRect?) {
        guard let visibleFrame else { window.center(); return }
        let size = window.frame.size
        let origin = NSPoint(x: visibleFrame.midX - size.width / 2,
                             y: visibleFrame.midY - size.height / 2)
        window.setFrameOrigin(origin)
    }

    private func makeMonitorWindow() -> NSWindow {
        let controller = NSHostingController(rootView: MonitorWindowRootView())
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "NeManeem"
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = true
        // Keep the monitor compact by default using the same content-driven minimum
        // column widths as the popover. Larger text or more columns increase the
        // required outer width instead of squeezing live values.
        let recommendedWidth = statusWindowRecommendedWidth(columns: activeStatusColumns(environment.settings.effectiveMonitorColumns, appBlockingEnabled: environment.firewallController.isEnabled), processMode: environment.settings.effectiveMonitorProcessDisplay, unitMode: environment.settings.effectiveMonitorUnitMode, directionDisplay: environment.settings.effectiveMonitorDirectionDisplay, scale: environment.settings.effectiveMonitorScale.factor, language: environment.settings.language)
        monitorLastRecommendedWidth = recommendedWidth
        window.contentMinSize = NSSize(width: recommendedWidth, height: 260)
        window.setContentSize(NSSize(width: max(recommendedWidth, 320), height: 360))
        window.setFrameAutosaveName(monitorFrameAutosaveName)
        window.delegate = self
        monitorWindow = window
        return window
    }

    private func monitorPresentationAnchorFrame() -> NSRect? {
        if let settingsWindow, settingsWindow.isVisible { return settingsWindow.frame }
        return NSApp.keyWindow?.frame ?? NSApp.mainWindow?.frame
    }

    private func hasValidSavedMonitorFrame() -> Bool {
        let key = "NSWindow Frame \(monitorFrameAutosaveName)"
        guard let encoded = UserDefaults.standard.string(forKey: key) else { return false }
        let saved = NSRectFromString(encoded)
        let visibleArea = NSScreen.screens.reduce(CGFloat.zero) { partial, screen in
            partial + saved.intersection(screen.visibleFrame).width * saved.intersection(screen.visibleFrame).height
        }
        if saved.width > 0, saved.height > 0, visibleArea >= 576 { return true }
        UserDefaults.standard.removeObject(forKey: key)
        return false
    }

    private func placeNewMonitorWindowIfNeeded(_ window: NSWindow,
                                                avoiding anchor: NSRect?,
                                                hasSavedFrame: Bool) {
        guard !hasSavedFrame else { return }
        let requested = environment.requestedPresentationScreenFrame
        environment.requestedPresentationScreenFrame = nil
        let screenFrame = requested
            ?? NSScreen.screens.first(where: { screen in anchor.map(screen.visibleFrame.intersects) ?? false })?.visibleFrame
            ?? NSApp.keyWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visible = screenFrame else { window.center(); return }
        guard let anchor else { center(window, on: visible); return }

        let gap: CGFloat = 12
        let size = window.frame.size
        func bounded(_ origin: NSPoint) -> NSRect {
            NSRect(x: min(max(origin.x, visible.minX), visible.maxX - size.width),
                   y: min(max(origin.y, visible.minY), visible.maxY - size.height),
                   width: size.width, height: size.height)
        }
        let centeredY = anchor.midY - size.height / 2
        let candidates = [
            bounded(NSPoint(x: anchor.maxX + gap, y: centeredY)),
            bounded(NSPoint(x: anchor.minX - gap - size.width, y: centeredY)),
            bounded(NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)),
            bounded(NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height))
        ]
        let best = candidates.min { lhs, rhs in
            let lhsOverlap = lhs.intersection(anchor).width * lhs.intersection(anchor).height
            let rhsOverlap = rhs.intersection(anchor).width * rhs.intersection(anchor).height
            return lhsOverlap == rhsOverlap ? lhs.origin.x > rhs.origin.x : lhsOverlap < rhsOverlap
        } ?? candidates[0]
        window.setFrame(best, display: false)
    }

    private func updateMonitorMinimumWidth() {
        guard let window = monitorWindow else { return }
        let minimumWidth = statusWindowRecommendedWidth(columns: activeStatusColumns(environment.settings.effectiveMonitorColumns, appBlockingEnabled: environment.firewallController.isEnabled), processMode: environment.settings.effectiveMonitorProcessDisplay, unitMode: environment.settings.effectiveMonitorUnitMode, directionDisplay: environment.settings.effectiveMonitorDirectionDisplay, scale: environment.settings.effectiveMonitorScale.factor, language: environment.settings.language)
        let previousMinimum = monitorLastRecommendedWidth ?? window.contentMinSize.width
        let compactReference = max(previousMinimum, 320)
        let currentContentWidth = window.contentView?.bounds.width ?? window.frame.width
        let currentContentHeight = window.contentView?.bounds.height ?? 360
        let userWasAtCompactWidth = currentContentWidth <= compactReference + 24
        monitorLastRecommendedWidth = minimumWidth
        window.contentMinSize = NSSize(width: minimumWidth, height: 260)

        // The monitor's numeric columns stay at their content minimum. Any extra
        // width belongs to the app/process name column, so a user can simply widen
        // the normal macOS window to reveal long names. Never shrink a window the
        // user deliberately enlarged; only keep compact windows aligned to the new
        // content minimum after display-size/column changes.
        if currentContentWidth < minimumWidth || userWasAtCompactWidth {
            window.setContentSize(NSSize(width: minimumWidth, height: currentContentHeight))
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === settingsWindow else { return frameSize }

        let preferredContentWidth: CGFloat = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityPreferredWidth
            : SettingsWindowLayoutMetrics.preferredWidth
        let preferredContentHeight: CGFloat = settingsUsesLargeAccessibilityText
            ? SettingsWindowLayoutMetrics.accessibilityPreferredHeight
            : SettingsWindowLayoutMetrics.preferredHeight
        let contentRect = NSRect(origin: .zero, size: NSSize(width: preferredContentWidth, height: preferredContentHeight))
        let fixedFrame = sender.frameRect(forContentRect: contentRect)

        switch environment.settings.settingsWindowSizeMode {
        case .free:
            return frameSize
        case .widthFixed:
            return NSSize(width: fixedFrame.width, height: frameSize.height)
        case .sizeFixed:
            return fixedFrame.size
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === settingsWindow {
            // Preview switches are temporary settings-window tools. Keep them stable
            // while moving between settings pages, then close them only when the
            // settings window itself is actually closed.
            if environment.popoverPreviewVisible {
                environment.popoverPreviewVisible = false
                environment.requestPopoverPreview?(false)
            }
            if environment.monitorPreviewVisible {
                environment.monitorPreviewVisible = false
                environment.requestMonitorPreview?(false)
            }
            releaseSettingsWindowIfNeeded(closing, deferred: true)
        }
        if closing === monitorWindow {
            closing.saveFrame(usingName: monitorFrameAutosaveName)
            let wasPreview = monitorPreviewOwned
            monitorPreviewOwned = false
            environment.appTrafficMonitor.setDemand(.monitorWindow, active: false)
            if wasPreview { environment.monitorPreviewVisible = false }
            releaseMonitorWindowIfNeeded(closing, deferred: true)
        }
    }

    /// Balanced and lower modes do not keep closed SwiftUI window trees alive.
    /// Performance mode intentionally keeps them warm for the fastest reopen.
    private var shouldReleaseClosedWindows: Bool {
        environment.settings.resourceMode != .performance
    }

    private func releaseHiddenWindowsIfAppropriate() {
        guard shouldReleaseClosedWindows else { return }
        if let window = settingsWindow, !window.isVisible {
            releaseSettingsWindowIfNeeded(window)
        }
        if let window = monitorWindow, !window.isVisible {
            releaseMonitorWindowIfNeeded(window)
        }
    }

    private func releaseSettingsWindowIfNeeded(_ window: NSWindow?, deferred: Bool = false) {
        guard shouldReleaseClosedWindows, let window, window === settingsWindow else { return }
        if deferred {
            Task { @MainActor [weak self, weak window] in
                guard let self, let window, window === self.settingsWindow, !window.isVisible else { return }
                window.contentViewController = nil
                self.settingsWindow = nil
            }
        } else {
            guard !window.isVisible else { return }
            window.contentViewController = nil
            settingsWindow = nil
        }
    }

    private func releaseMonitorWindowIfNeeded(_ window: NSWindow?, deferred: Bool = false) {
        guard shouldReleaseClosedWindows, let window, window === monitorWindow else { return }
        if deferred {
            Task { @MainActor [weak self, weak window] in
                guard let self, let window, window === self.monitorWindow, !window.isVisible else { return }
                window.contentViewController = nil
                self.monitorWindow = nil
                self.monitorLastRecommendedWidth = nil
            }
        } else {
            guard !window.isVisible else { return }
            window.contentViewController = nil
            monitorWindow = nil
            monitorLastRecommendedWidth = nil
        }
    }
}

/// Canonical top-level Settings order. Declaration order is the sidebar order and
/// the same cases drive navigation, search destinations and content switching.
