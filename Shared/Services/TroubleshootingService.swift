import AppKit
import Combine
import CryptoKit
import Foundation

struct TroubleshootingSnapshot: Sendable {
    let createdAt: Date
    let appVersion: String
    let appBuild: String
    let macOSVersion: String
    let appIsInApplications: Bool
    let filterConfigured: Bool
    let packagedFilterVersionMatchesHost: Bool?
    let extensionNeedsUserApproval: Bool
    let monitoringPermissionRequestRecommended: Bool
    let trafficMonitorRunning: Bool
    let trafficConnected: Bool
    let connectionFailureCount: Int
    let trafficErrorPresent: Bool
    let filterStatusErrorPresent: Bool
    let wiFiIdentity: WiFiIdentityDiagnosticSnapshot
}

struct TroubleshootingReport: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let sha256: String
    let createdAt: Date
    let appVersion: String
    let appBuild: String
}

@MainActor
final class TroubleshootingService: ObservableObject {
    @Published private(set) var isDiagnosing = false
    @Published private(set) var isCheckingMeasurementEngine = false
    @Published private(set) var isGeneratingReport = false
    @Published private(set) var snapshot: TroubleshootingSnapshot?
    @Published private(set) var report: TroubleshootingReport?
    @Published private(set) var errorMessage: String?

    private var diagnosticDemandWasAdded = false
    private var recentDiagnosticEvents: [String] = []

    func runDiagnosis(firewall: FirewallController,
                      traffic: AppTrafficMonitor,
                      interface: NetworkInterfaceMonitor,
                      knownNetworkCount: Int) async {
        guard !isDiagnosing else { return }
        isDiagnosing = true
        errorMessage = nil
        recordEvent("diagnosisStarted")

        // Run the exact per-app XPC path only while the user explicitly diagnoses.
        // No background troubleshooting monitor remains after this check.
        traffic.setDemand(.troubleshooting, active: true)
        diagnosticDemandWasAdded = true

        // An approved Network Extension may need a few seconds to reconnect its
        // passive XPC measurement channel. Do not reconfigure, re-activate, save
        // preferences, or reinstall anything here: diagnose what macOS is already
        // doing, then report the final observed state.
        var current = Self.makeSnapshot(firewall: firewall, traffic: traffic, interface: interface, knownNetworkCount: knownNetworkCount)
        if firewall.engineIsEnabled && traffic.isRunning && !current.trafficConnected {
            isCheckingMeasurementEngine = true
            for delay in [500_000_000, 1_000_000_000, 1_500_000_000, 2_000_000_000, 2_000_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                current = Self.makeSnapshot(firewall: firewall, traffic: traffic, interface: interface, knownNetworkCount: knownNetworkCount)
                if current.trafficConnected { break }
            }
            isCheckingMeasurementEngine = false
        }
        snapshot = current
        recordEvent(current.trafficConnected ? "measurementConnectionObserved" : "measurementConnectionUnavailable")

        if diagnosticDemandWasAdded {
            traffic.setDemand(.troubleshooting, active: false)
            diagnosticDemandWasAdded = false
        }
        isCheckingMeasurementEngine = false
        isDiagnosing = false
    }

    func generateReport(firewall: FirewallController,
                        traffic: AppTrafficMonitor,
                        interface: NetworkInterfaceMonitor,
                        knownNetworkCount: Int) async {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true
        errorMessage = nil

        let current = Self.makeSnapshot(firewall: firewall, traffic: traffic, interface: interface, knownNetworkCount: knownNetworkCount)
        snapshot = current
        recordEvent("reportSnapshotGenerated")

        do {
            let text = Self.reportText(snapshot: current, recentEvents: recentDiagnosticEvents)
            let data = Data(text.utf8)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let url = try Self.writeTemporaryReport(data: data)
            report = TroubleshootingReport(url: url,
                                           sha256: digest,
                                           createdAt: Date(),
                                           appVersion: current.appVersion,
                                           appBuild: current.appBuild)
        } catch {
            errorMessage = error.localizedDescription
        }

        isGeneratingReport = false
    }

    func openCurrentAppLocation() {
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    func openReport() {
        guard let report else { return }
        NSWorkspace.shared.open(report.url)
    }

    @discardableResult
    func composeEmail() -> Bool {
        guard let report,
              let service = NSSharingService(named: .composeEmail) else { return false }

        service.recipients = ["creative2ya@gmail.com"]
        service.subject = "[NeManeem 오류 보고] v\(report.appVersion) Build \(report.appBuild)"
        service.perform(withItems: [Self.emailBody(report: report) as NSString, report.url])
        return true
    }

    private static func makeSnapshot(firewall: FirewallController,
                                     traffic: AppTrafficMonitor,
                                     interface: NetworkInterfaceMonitor,
                                     knownNetworkCount: Int) -> TroubleshootingSnapshot {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let inApplications = path == "/Applications/NeManeem.app" || path.hasPrefix("/Applications/")
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let connected = traffic.hasCompletedInitialSample && traffic.errorMessage == nil

        return TroubleshootingSnapshot(createdAt: Date(),
                                       appVersion: version,
                                       appBuild: build,
                                       macOSVersion: os,
                                       appIsInApplications: inApplications,
                                       filterConfigured: firewall.engineIsEnabled,
                                       packagedFilterVersionMatchesHost: packagedFilterVersionMatchesHost(version: version, build: build),
                                       extensionNeedsUserApproval: firewall.extensionNeedsUserApproval,
                                       monitoringPermissionRequestRecommended: firewall.monitoringPermissionRequestRecommended,
                                       trafficMonitorRunning: traffic.isRunning,
                                       trafficConnected: connected,
                                       connectionFailureCount: traffic.connectionFailureCount,
                                       trafficErrorPresent: traffic.errorMessage != nil,
                                       filterStatusErrorPresent: firewall.statusMessage != nil,
                                       wiFiIdentity: interface.makeWiFiIdentityDiagnosticSnapshot(knownNetworkCount: knownNetworkCount))
    }

    private static func reportText(snapshot: TroubleshootingSnapshot,
                                   recentEvents: [String]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        let filterVersionMatch = snapshot.packagedFilterVersionMatchesHost.map(String.init(describing:)) ?? "notAvailable"
        let events = recentEvents.isEmpty ? "none" : recentEvents.joined(separator: "\n")

        return """
        NeManeem Diagnostic Report
        Report format: NeManeemDiagnostics/2
        Encoding: UTF-8 plain text
        Executable content: none
        Generated: \(timestamp)

        [PRIVACY NOTICE]
        This report contains only the minimum technical states needed for troubleshooting.
        It does not include Wi-Fi names (SSIDs), BSSIDs, location coordinates, URLs, domains,
        IP addresses, packet contents, browsing history, user names, home-directory paths,
        developer account identifiers, bundle identifiers, App Group names, Mach service names,
        or previous NeManeem version and extension history. Review before sharing.

        [APP]
        Version: \(snapshot.appVersion)
        Build: \(snapshot.appBuild)
        macOS: \(snapshot.macOSVersion)
        Installed in Applications: \(snapshot.appIsInApplications)

        [NETWORK EXTENSION]
        Configured/enabled: \(snapshot.filterConfigured)
        Current extension active: \(snapshot.filterConfigured)
        Packaged Host/Filter version match: \(filterVersionMatch)
        User approval currently required: \(snapshot.extensionNeedsUserApproval)
        Permission action currently recommended: \(snapshot.monitoringPermissionRequestRecommended)
        Status error present: \(snapshot.filterStatusErrorPresent)

        [MEASUREMENT]
        Traffic monitor running: \(snapshot.trafficMonitorRunning)
        Initial traffic snapshot received: \(snapshot.trafficConnected)
        Consecutive connection failures: \(snapshot.connectionFailureCount)
        Technical error present: \(snapshot.trafficErrorPresent)

        [WIFI IDENTITY]
        Sandbox enabled: \(snapshot.wiFiIdentity.sandboxEnabled)
        Location authorization: \(snapshot.wiFiIdentity.locationAuthorization)
        Wi-Fi client available: \(snapshot.wiFiIdentity.clientAvailable)
        interface() resolved: \(snapshot.wiFiIdentity.primaryInterfaceResolved)
        interfaces() count: \(snapshot.wiFiIdentity.interfacesCount)
        interfaceNames() count: \(snapshot.wiFiIdentity.interfaceNamesCount)
        interface(withName:) resolved: \(snapshot.wiFiIdentity.interfaceWithNameResolved)
        OS Wi-Fi candidate available: \(snapshot.wiFiIdentity.osWiFiCandidateAvailable)
        Saved Wi-Fi profiles count: \(snapshot.wiFiIdentity.savedWiFiProfilesCount)
        Known network count: \(snapshot.wiFiIdentity.knownNetworkCount)
        Nearby network result count: \(snapshot.wiFiIdentity.nearbyNetworkResultCount)
        Wi-Fi interface available: \(snapshot.wiFiIdentity.interfaceAvailable)
        Wi-Fi interface name: \(snapshot.wiFiIdentity.interfaceName ?? "none")
        Wi-Fi service available: \(snapshot.wiFiIdentity.serviceAvailable)
        Wi-Fi powered: \(snapshot.wiFiIdentity.powered)
        SSID present: \(snapshot.wiFiIdentity.ssidPresent)
        Current path uses VPN/utun: \(snapshot.wiFiIdentity.currentPathUsesVPN)
        Reliable Wi-Fi identity selected: \(snapshot.wiFiIdentity.reliableWiFiIdentitySelected)

        [RECENT DIAGNOSTIC EVENTS]
        \(events)

        [END OF REPORT]
        """
    }

    private func recordEvent(_ name: String) {
        let formatter = ISO8601DateFormatter()
        recentDiagnosticEvents.append("\(formatter.string(from: Date())) \(name)")
        if recentDiagnosticEvents.count > 12 {
            recentDiagnosticEvents.removeFirst(recentDiagnosticEvents.count - 12)
        }
    }

    private static func packagedFilterVersionMatchesHost(version: String, build: String) -> Bool? {
        let extensionsURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: extensionsURL,
                                                                           includingPropertiesForKeys: nil) else {
            return nil
        }
        for entry in entries where entry.pathExtension == "systemextension" {
            let infoURL = entry.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: infoURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  plist["CFBundleIdentifier"] as? String == AppConstants.filterBundleIdentifier else { continue }
            return plist["CFBundleShortVersionString"] as? String == version &&
                String(describing: plist["CFBundleVersion"] ?? "") == build
        }
        return nil
    }

    private nonisolated static func emailBody(report: TroubleshootingReport) -> String {
        // Keep the creator-facing template in Korean, matching the fixed creator signature/contact.
        """
        안녕하세요. NeManeem 오류 보고입니다.

        [문제가 발생한 상황]
        어떤 작업을 하던 중이었는지 적어주세요.

        [발생한 문제]
        어떤 문제가 발생했는지 적어주세요.

        [다시 발생시키는 방법 - 알고 있다면]
        같은 문제가 다시 생기는 순서를 적어주세요.

        첨부파일: \(report.url.lastPathComponent)
        파일 형식: UTF-8 평문 TXT (실행 파일이 아닙니다.)
        SHA-256: \(report.sha256)

        첨부파일의 SHA-256이 위 값과 다르면 NeManeem이 보고서를 만든 뒤 파일 내용이 변경된 것입니다.
        SHA-256은 파일 내용의 무결성을 확인하기 위한 값이며, 보낸 사람의 신원 자체를 인증하는 전자서명은 아닙니다.

        NeManeem에서 생성한 진단 보고서를 첨부했습니다.
        실제 전송은 이 메일의 보내기 버튼을 누를 때만 이루어집니다.
        """
    }

    private nonisolated static func writeTemporaryReport(data: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeManeemDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Privacy-first cleanup: keep only the newly generated report in NeManeem's temp folder.
        if let oldFiles = try? FileManager.default.contentsOfDirectory(at: root,
                                                                        includingPropertiesForKeys: nil) {
            for file in oldFiles where file.pathExtension.lowercased() == "txt" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "NeManeem_Diagnostics_\(formatter.string(from: Date())).txt"
        let url = root.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

}
