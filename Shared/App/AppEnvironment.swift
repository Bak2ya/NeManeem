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
    }
}
