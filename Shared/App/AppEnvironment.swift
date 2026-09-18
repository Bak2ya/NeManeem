import AppKit
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let settings: SettingsStore
    let interfaceMonitor: NetworkInterfaceMonitor
    let appTrafficMonitor: AppTrafficMonitor
    let firewallController: FirewallController
    let usageRecorder: UsageRecorder
    let loginItemController: LoginItemController
    private var cancellables = Set<AnyCancellable>()

    @Published var requestedSettingsDestination: String?
    @Published var popoverPreviewVisible = false
    @Published var monitorPreviewVisible = false
    var requestWindowMode: ((MainWindowMode) -> Void)?
    var requestSettingsSection: ((String) -> Void)?
    var requestPopoverPreview: ((Bool) -> Void)?
    var requestMonitorPreview: ((Bool) -> Void)?
    var requestResetSettingsWindowSize: (() -> Void)?
    var requestResetMonitorWindowSize: (() -> Void)?
    var requestSettingsAccessibilityLayout: ((Bool) -> Void)?
    /// Screen preference captured from the UI that initiated a new window. This
    /// keeps multi-display flows on the monitor the user is actually working on.
    var requestedPresentationScreenFrame: NSRect?

    func clearTemporaryCaches(includeNetworkChoices: Bool = true) {
        appTrafficMonitor.clearTemporaryCaches()
        usageRecorder.clearTemporaryCaches()
        if includeNetworkChoices { interfaceMonitor.clearTemporaryCaches() }
    }

    private init() {
        let settings = SettingsStore()
        let interfaceMonitor = NetworkInterfaceMonitor()
        let appTrafficMonitor = AppTrafficMonitor()
        let firewallController = FirewallController()
        self.settings = settings
        self.interfaceMonitor = interfaceMonitor
        self.appTrafficMonitor = appTrafficMonitor
        self.firewallController = firewallController
        self.usageRecorder = UsageRecorder(settings: settings,
                                           interfaceMonitor: interfaceMonitor,
                                           appTrafficMonitor: appTrafficMonitor,
                                           firewallController: firewallController)
        self.loginItemController = LoginItemController()

        settings.$safariNetworkServiceGroupingEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { _ in
                Task { @MainActor in
                    appTrafficMonitor.refreshCompatibilityPresentation()
                    firewallController.refreshCompatibilityPolicy()
                }
            }
            .store(in: &cancellables)

        // Blocking safety reuses the existing Host <-> System Extension XPC road.
        // Normal traffic snapshot requests count as liveness automatically; when no
        // UI or recorder needs snapshots, AppTrafficMonitor falls back to one tiny
        // liveness call roughly every 30 seconds.
        Publishers.CombineLatest3(
            firewallController.$engineIsEnabled.removeDuplicates(),
            firewallController.$isEnabled.removeDuplicates(),
            firewallController.$isDataLimitInternetBlocked.removeDuplicates()
        )
        .map { engineEnabled, appBlockingEnabled, dataLimitBlocked in
            engineEnabled && (appBlockingEnabled || dataLimitBlocked)
        }
        .removeDuplicates()
        .sink { active in
            appTrafficMonitor.setDemand(.blockingSafety, active: active)
        }
        .store(in: &cancellables)
    }
}
