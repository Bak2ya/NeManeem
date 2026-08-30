import AppKit
import Combine
import CoreLocation
import CoreWLAN
import Darwin
import Foundation
import Network

struct WiFiNetworkChoice: Identifiable, Equatable {
    let ssid: String
    var id: String { "wifi:ssid:\(ssid)" }
    var displayName: String { ssid }
}

/// A report-only, direct CoreWLAN/CoreLocation observation. It intentionally
/// contains stage booleans rather than SSID/BSSID/location/network-content data.
struct WiFiIdentityDiagnosticSnapshot: Sendable {
    let locationAuthorization: String
    let sandboxEnabled: Bool
    let clientAvailable: Bool
    let interfacesCount: Int
    let primaryInterfaceResolved: Bool
    let interfaceNamesCount: Int
    let interfaceWithNameResolved: Bool
    let osWiFiCandidateAvailable: Bool
    let savedWiFiProfilesCount: Int
    let knownNetworkCount: Int
    let nearbyNetworkResultCount: Int
    let interfaceAvailable: Bool
    let interfaceName: String?
    let serviceAvailable: Bool
    let powered: Bool
    let ssidPresent: Bool
    let currentPathUsesVPN: Bool
    let reliableWiFiIdentitySelected: Bool
}

// DispatchSourceTimer and NWPathMonitor invoke this reference from the dedicated
// workerQueue. UI-facing @Published mutations are hopped back to MainActor. The
// object deliberately owns that cross-queue lifetime, so declare the audited
// reference container as unchecked Sendable instead of capturing a non-Sendable
// NSObject in Dispatch's @Sendable closures.
final class NetworkInterfaceMonitor: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    @Published private(set) var snapshot = NetworkSnapshot()
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var savedWiFiNetworks: [WiFiNetworkChoice] = []
    @Published private(set) var nearbyWiFiNetworks: [WiFiNetworkChoice] = []
    @Published private(set) var isScanningWiFiNetworks = false
    @Published private(set) var locationServicesEnabled = CLLocationManager.locationServicesEnabled()
    @Published private(set) var currentPathUsesVPN = false
    @Published private(set) var osWiFiCandidateInterfaceNames: [String] = []

    private let workerQueue = DispatchQueue(label: "NeManeem.InterfaceMonitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastCounters: (received: UInt64, sent: UInt64)?
    private var lastDate: Date?
    private var refreshInterval: TimeInterval = 3.0
    private let pathMonitor = NWPathMonitor()
    private var locationManager: CLLocationManager?
    private var currentPath: NWPath?
    private var currentInterfaceDescription = "Network"
    private var currentPrimaryInterfaceName = ""
    private var currentNetworkIdentifier = ""
    private var currentNetworkDisplayName = ""
    private var currentNetworkIdentityReliable = false
    private var interfaceTypes: [String: NWInterface.InterfaceType] = [:]
    private var workerWiFiCandidateInterfaceNames: [String] = []
    private var wiFiIdentityByInterface: [String: (identifier: String, displayName: String, reliable: Bool)] = [:]
    private var pathMonitorStarted = false
    @MainActor private var locationPromptPreviousActivationPolicy: NSApplication.ActivationPolicy?

    override init() {
        super.init()
        // CoreLocation/CoreWLAN are intentionally NOT initialized during app launch.
        // NeManeem can start and show its menu-bar UI without Wi-Fi-name access;
        // SSID support is activated only after the user explicitly asks for it.
    }

    var wiFiIdentityAuthorized: Bool {
        locationAuthorizationStatus != .notDetermined &&
        locationAuthorizationStatus != .denied &&
        locationAuthorizationStatus != .restricted
    }
    var wiFiIdentityAuthorizationDenied: Bool {
        locationAuthorizationStatus == .denied || locationAuthorizationStatus == .restricted
    }

    /// Reads the currently observable SSID acquisition stages for a user-requested
    /// diagnostic report. This neither asks for permission nor changes network,
    /// extension, saved-choice, or identity-cache state.
    @MainActor
    func makeWiFiIdentityDiagnosticSnapshot(knownNetworkCount: Int) -> WiFiIdentityDiagnosticSnapshot {
        let servicesEnabled = CLLocationManager.locationServicesEnabled()
        let authorization = CLLocationManager().authorizationStatus
        let resolution = resolveWiFiInterfaces(candidateInterfaceNames: osWiFiCandidateInterfaceNames)
        let selected = resolution.primary ?? resolution.interfaces.first(where: { $0.serviceActive() }) ?? resolution.interfaces.first
        let interfaceName = selected?.interfaceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceAvailable = selected?.serviceActive() ?? false
        let powered = selected?.powerOn() ?? false
        // CoreWLAN access is only attempted after the user has granted the
        // optional Wi-Fi-name permission. The boolean is enough to diagnose the
        // stage and prevents a report from ever retaining the actual Wi-Fi name.
        let isAuthorized = servicesEnabled && authorization != .notDetermined && authorization != .denied && authorization != .restricted
        let ssidPresent = isAuthorized && !(selected?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let reliableWiFiSelected = snapshot.networkIdentityReliable && snapshot.networkIdentifier.hasPrefix("wifi:ssid:")

        return WiFiIdentityDiagnosticSnapshot(
            locationAuthorization: Self.locationAuthorizationDescription(authorization, servicesEnabled: servicesEnabled),
            sandboxEnabled: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
            clientAvailable: resolution.clientAvailable,
            interfacesCount: resolution.interfaces.count,
            primaryInterfaceResolved: resolution.primary != nil,
            interfaceNamesCount: resolution.interfaceNamesCount,
            interfaceWithNameResolved: resolution.interfaceWithNameResolved,
            osWiFiCandidateAvailable: !osWiFiCandidateInterfaceNames.isEmpty,
            savedWiFiProfilesCount: savedWiFiNetworks.count,
            knownNetworkCount: knownNetworkCount,
            nearbyNetworkResultCount: nearbyWiFiNetworks.count,
            interfaceAvailable: selected != nil,
            interfaceName: interfaceName?.isEmpty == false ? interfaceName : nil,
            serviceAvailable: serviceAvailable,
            powered: powered,
            ssidPresent: ssidPresent,
            currentPathUsesVPN: currentPathUsesVPN,
            reliableWiFiIdentitySelected: reliableWiFiSelected
        )
    }

    private static func locationAuthorizationDescription(_ status: CLAuthorizationStatus,
                                                         servicesEnabled: Bool) -> String {
        guard servicesEnabled else { return "locationServicesDisabled" }
        switch status {
        case .notDetermined: return "notDetermined"
        case .authorizedAlways, .authorizedWhenInUse: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    /// Centralize public CoreWLAN interface acquisition. `client.interface()` is
    /// the primary current-interface path; `interfaces()` is the fallback used
    /// for current identity, saved profiles, nearby scanning, and diagnostics.
    /// The resolver never creates a CWInterface directly and does not prompt.
    private struct WiFiInterfaceResolution {
        let clientAvailable: Bool
        let primary: CWInterface?
        let interfaces: [CWInterface]
        let interfaceNamesCount: Int
        let interfaceWithNameResolved: Bool
    }

    private func resolveWiFiInterfaces(candidateInterfaceNames: [String] = []) -> WiFiInterfaceResolution {
        let client = CWWiFiClient.shared()
        let primary = client.interface()
        var interfaces: [CWInterface] = []
        if let primary { interfaces.append(primary) }
        for candidate in client.interfaces() ?? [] {
            appendWiFiInterface(candidate, to: &interfaces)
        }
        let interfaceNames = client.interfaceNames() ?? []
        let namesToResolve = Set(interfaceNames).union(candidateInterfaceNames)
        var interfaceWithNameResolved = false
        for name in namesToResolve where !name.isEmpty {
            guard let named = client.interface(withName: name) else { continue }
            interfaceWithNameResolved = true
            appendWiFiInterface(named, to: &interfaces)
        }
        return WiFiInterfaceResolution(clientAvailable: true,
                                       primary: primary,
                                       interfaces: interfaces,
                                       interfaceNamesCount: interfaceNames.count,
                                       interfaceWithNameResolved: interfaceWithNameResolved)
    }

    private func appendWiFiInterface(_ candidate: CWInterface, to interfaces: inout [CWInterface]) {
        let candidateName = candidate.interfaceName ?? ""
        let alreadyIncluded = interfaces.contains { existing in
            existing === candidate || (!candidateName.isEmpty && existing.interfaceName == candidateName)
        }
        if !alreadyIncluded { interfaces.append(candidate) }
    }

    @MainActor
    func clearTemporaryCaches() {
        savedWiFiNetworks = []
        nearbyWiFiNetworks = []
        isScanningWiFiNetworks = false
    }

    func requestWiFiIdentityAuthorization() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshWiFiIdentityAuthorizationStatusOnMainActor()
            guard self.locationServicesEnabled else { return }

            // Core Location presents a When-In-Use prompt only for a foreground
            // application. LSUIElement normally runs as an accessory app, so for
            // this explicit user action only, temporarily become a regular app,
            // activate, request permission, then restore the original policy in the
            // authorization callback. No permission is requested at launch.
            self.prepareForegroundForLocationPrompt()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.requestWiFiIdentityAuthorizationOnMainActor()
            }
        }
    }

    func refreshWiFiIdentityAuthorizationStatus() {
        Task { @MainActor [weak self] in
            self?.refreshWiFiIdentityAuthorizationStatusOnMainActor()
        }
    }

    /// Called only from the user's Data Limit network chooser. A scan is never
    /// scheduled in the background or on the normal byte-sampling path.
    func refreshWiFiNetworkChoices(scanNearby: Bool = true) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.prepareLocationManagerWithoutPrompt()
            guard self.wiFiIdentityAuthorized else { return }
            self.isScanningWiFiNetworks = scanNearby
            self.workerQueue.async { [weak self] in
                self?.collectWiFiNetworkChoices(scanNearby: scanNearby)
            }
        }
    }

    @MainActor
    private func refreshWiFiIdentityAuthorizationStatusOnMainActor() {
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        prepareLocationManagerWithoutPrompt()
        // If the user already granted Location access for SSID identification,
        // rebuild the CoreWLAN identity cache immediately. This never prompts and
        // prevents a relaunch/path refresh from falling back to `Wi-Fi (en0)` or an
        // utun/interface label while a real SSID is already available.
        if wiFiIdentityAuthorized {
            refreshWiFiIdentityCacheAfterAuthorization()
        }
    }

    @MainActor
    private func prepareLocationManagerWithoutPrompt() {
        if locationManager == nil {
            let created = CLLocationManager()
            created.delegate = self
            locationManager = created
        }
        // Re-read the process-wide permission as well as the manager value. This
        // catches the common macOS case where Location Services stays ON but the
        // NeManeem switch itself is changed in System Settings while the app runs.
        let freshStatus = CLLocationManager().authorizationStatus
        let managerStatus = locationManager?.authorizationStatus ?? freshStatus
        locationAuthorizationStatus = freshStatus != .notDetermined ? freshStatus : managerStatus
    }

    @MainActor
    private func requestWiFiIdentityAuthorizationOnMainActor() {
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        guard locationServicesEnabled else { return }

        let manager: CLLocationManager
        if let existing = locationManager {
            manager = existing
        } else {
            let created = CLLocationManager()
            created.delegate = self
            locationManager = created
            manager = created
        }

        let status = manager.authorizationStatus
        locationAuthorizationStatus = status
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            restoreActivationPolicyAfterLocationPrompt()
            applyLocationAuthorization(status)
        }
    }

    @MainActor
    private func prepareForegroundForLocationPrompt() {
        if locationPromptPreviousActivationPolicy == nil {
            locationPromptPreviousActivationPolicy = NSApp.activationPolicy()
        }
        if NSApp.activationPolicy() != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func restoreActivationPolicyAfterLocationPrompt() {
        guard let previous = locationPromptPreviousActivationPolicy else { return }
        locationPromptPreviousActivationPolicy = nil
        if NSApp.activationPolicy() != previous {
            _ = NSApp.setActivationPolicy(previous)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            if status != .notDetermined {
                self.restoreActivationPolicyAfterLocationPrompt()
            }
            self.applyLocationAuthorization(status)
        }
    }

    @MainActor
    private func applyLocationAuthorization(_ status: CLAuthorizationStatus) {
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        locationAuthorizationStatus = status
        guard status != .notDetermined, status != .denied, status != .restricted else {
            return
        }
        refreshWiFiIdentityCacheAfterAuthorization()
        refreshWiFiNetworkChoices(scanNearby: true)
    }

    @MainActor
    private func refreshWiFiIdentityCacheAfterAuthorization() {
        // CoreWLAN is touched only after the user opted into Wi-Fi-name identity.
        // On launch this is called only after the visible menu-bar UI exists and only
        // for an already-authorized user, so it can restore the real SSID without a prompt.
        var values: [String: (identifier: String, displayName: String, reliable: Bool)] = [:]
        for wifi in resolveWiFiInterfaces(candidateInterfaceNames: osWiFiCandidateInterfaceNames).interfaces {
            guard let name = wifi.interfaceName, !name.isEmpty else { continue }
            let serviceActive = wifi.serviceActive()
            let ssid = wifi.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard serviceActive else { continue }
            if !ssid.isEmpty {
                values[name] = ("wifi:ssid:\(ssid)", ssid, true)
            } else {
                values[name] = ("wifi:interface:\(name)", "Wi-Fi (\(name))", false)
            }
        }

        workerQueue.async { [weak self] in
            guard let self else { return }
            self.wiFiIdentityByInterface = values
            guard let path = self.currentPath else { return }
            let identity = self.primaryIdentity(for: path)
            self.applyCachedIdentity(identity)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.snapshot.interfaceDescription = identity.description
                self.snapshot.networkIdentifier = identity.identifier
                self.snapshot.networkDisplayName = identity.displayName
                self.snapshot.networkIdentityReliable = identity.reliable
            }
        }
    }

    private func collectWiFiNetworkChoices(scanNearby: Bool) {
        var saved: [String: WiFiNetworkChoice] = [:]
        var nearby: [String: WiFiNetworkChoice] = [:]
        var currentSSIDs: Set<String> = []
        var identityValues: [String: (identifier: String, displayName: String, reliable: Bool)] = [:]

        for wifi in resolveWiFiInterfaces(candidateInterfaceNames: workerWiFiCandidateInterfaceNames).interfaces {
            guard let interfaceName = wifi.interfaceName, !interfaceName.isEmpty else { continue }
            if let ssid = wifi.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty {
                currentSSIDs.insert(ssid)
                identityValues[interfaceName] = ("wifi:ssid:\(ssid)", ssid, true)
            }

            if let profiles = wifi.configuration()?.networkProfiles {
                for profile in profiles.array.compactMap({ $0 as? CWNetworkProfile }) {
                    guard let ssid = profile.ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty else { continue }
                    saved[ssid] = WiFiNetworkChoice(ssid: ssid)
                }
            }

            let scanResults: Set<CWNetwork>
            if scanNearby {
                scanResults = (try? wifi.scanForNetworks(withSSID: nil)) ?? wifi.cachedScanResults() ?? []
            } else {
                scanResults = wifi.cachedScanResults() ?? []
            }
            for network in scanResults {
                guard let ssid = network.ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !ssid.isEmpty else { continue }
                nearby[ssid] = WiFiNetworkChoice(ssid: ssid)
            }
        }

        // Show each SSID only once in the chooser hierarchy: current connection
        // first, then remembered networks, then nearby-only results.
        let savedValues = saved.values
            .filter { !currentSSIDs.contains($0.ssid) }
            .sorted { $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending }
        let savedNames = Set(saved.keys)
        let nearbyValues = nearby.values
            .filter { !currentSSIDs.contains($0.ssid) && !savedNames.contains($0.ssid) }
            .sorted { $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending }
        wiFiIdentityByInterface.merge(identityValues) { _, new in new }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.savedWiFiNetworks = savedValues
            self.nearbyWiFiNetworks = nearbyValues
            self.isScanningWiFiNetworks = false
            self.refreshWiFiIdentityCacheAfterAuthorization()
        }
    }

    func start(refreshInterval: TimeInterval) {
        self.refreshInterval = max(0.25, refreshInterval)
        if !pathMonitorStarted {
            startPathMonitor()
            pathMonitorStarted = true
        }
        restartTimer()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if pathMonitorStarted { pathMonitor.cancel() }
    }

    func setRefreshInterval(_ seconds: TimeInterval) {
        refreshInterval = max(0.25, seconds)
        restartTimer()
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.currentPath = path
            // Do not use Dictionary(uniqueKeysWithValues:) with system-provided
            // interface lists. A duplicate interface name must never be able to
            // terminate the menu-bar host process at runtime.
            var types: [String: NWInterface.InterfaceType] = [:]
            for interface in path.availableInterfaces {
                types[interface.name] = interface.type
            }
            self.interfaceTypes = types
            self.workerWiFiCandidateInterfaceNames = path.availableInterfaces
                .filter { $0.type == .wifi }
                .map(\.name)
            let identity = self.primaryIdentity(for: path)
            self.applyCachedIdentity(identity)
            // A VPN route can become the NWPath primary interface after the Wi-Fi
            // cache was last refreshed. Re-check the already-authorized CoreWLAN
            // cache on this path transition only; this neither prompts nor runs on
            // the normal traffic-sampling loop.
            if path.availableInterfaces.contains(where: { $0.name.hasPrefix("utun") }) {
                Task { @MainActor [weak self] in
                    self?.refreshWiFiIdentityAuthorizationStatusOnMainActor()
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentPathUsesVPN = path.availableInterfaces.contains(where: { $0.name.hasPrefix("utun") })
                self.osWiFiCandidateInterfaceNames = path.availableInterfaces
                    .filter { $0.type == .wifi }
                    .map(\.name)
                self.snapshot.interfaceDescription = identity.description
                self.snapshot.networkIdentifier = identity.identifier
                self.snapshot.networkDisplayName = identity.displayName
                self.snapshot.networkIdentityReliable = identity.reliable
            }
        }
        pathMonitor.start(queue: workerQueue)
    }

    private struct Identity {
        let interfaceName: String
        let description: String
        let identifier: String
        let displayName: String
        let reliable: Bool
    }

    private func applyCachedIdentity(_ identity: Identity) {
        currentPrimaryInterfaceName = identity.interfaceName
        currentInterfaceDescription = identity.description
        currentNetworkIdentifier = identity.identifier
        currentNetworkDisplayName = identity.displayName
        currentNetworkIdentityReliable = identity.reliable
    }

    private func primaryIdentity(for path: NWPath) -> Identity {
        guard path.status == .satisfied else {
            return Identity(interfaceName: "", description: "No Connection", identifier: "", displayName: "", reliable: false)
        }

        if path.usesInterfaceType(.wifi) {
            // CoreWLAN SSID access is deliberately refreshed only when the path or
            // Location authorization changes, not on every 0.25–10 s byte sample.
            let name = path.availableInterfaces.first(where: { $0.type == .wifi })?.name ?? "wifi"
            if let cached = wiFiIdentityByInterface[name] {
                return Identity(interfaceName: name, description: "Wi-Fi", identifier: cached.identifier, displayName: cached.displayName, reliable: cached.reliable)
            }
            return Identity(interfaceName: name, description: "Wi-Fi", identifier: "wifi:interface:\(name)", displayName: "Wi-Fi (\(name))", reliable: false)
        }
        if path.usesInterfaceType(.wiredEthernet) {
            let name = path.availableInterfaces.first(where: { $0.type == .wiredEthernet })?.name ?? "ethernet"
            return Identity(interfaceName: name, description: "Ethernet", identifier: "ethernet:interface:\(name)", displayName: "Ethernet (\(name))", reliable: false)
        }
        if path.usesInterfaceType(.cellular) {
            let name = path.availableInterfaces.first(where: { $0.type == .cellular })?.name ?? "cellular"
            return Identity(interfaceName: name, description: "Cellular", identifier: "cellular:interface:\(name)", displayName: "Cellular (\(name))", reliable: false)
        }
        if let other = path.availableInterfaces.first(where: { $0.type != .loopback }) {
            // A VPN/content-filter path can expose utun as the primary route even
            // while the physical connection is Wi-Fi. For user-facing network
            // identity, prefer an authorized active CoreWLAN SSID in that case;
            // keep the utun name as expert-only transport detail.
            if other.name.hasPrefix("utun"),
               let wifi = wiFiIdentityByInterface.first(where: { $0.value.reliable }) {
                return Identity(interfaceName: wifi.key, description: "Wi-Fi", identifier: wifi.value.identifier, displayName: wifi.value.displayName, reliable: true)
            }
            return Identity(interfaceName: other.name, description: "Network", identifier: "network:interface:\(other.name)", displayName: "Network (\(other.name))", reliable: false)
        }
        return Identity(interfaceName: "", description: "Network", identifier: "", displayName: "", reliable: false)
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        lastCounters = nil
        lastDate = nil

        let newTimer = DispatchSource.makeTimerSource(queue: workerQueue)
        let milliseconds = max(250, Int(min(refreshInterval, 86_400) * 1000))
        let tolerance = min(100, max(10, Int(Double(milliseconds) * 0.08)))
        newTimer.schedule(deadline: .now(), repeating: .milliseconds(milliseconds), leeway: .milliseconds(tolerance))
        newTimer.setEventHandler { [weak self] in self?.sample() }
        timer = newTimer
        newTimer.resume()
    }

    private struct RawCounter {
        let name: String
        let received: UInt64
        let sent: UInt64
    }

    private func readCounters() -> (received: UInt64, sent: UInt64, interfaces: [RawCounter]) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0, []) }
        defer { freeifaddrs(pointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var interfaces: [RawCounter] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        var seen = Set<String>()

        while let item = cursor?.pointee {
            let name = String(cString: item.ifa_name)
            let flags = Int32(item.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, isRunning, !isLoopback, shouldCountInterface(name), !seen.contains(name), let dataPointer = item.ifa_data {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                let rx = UInt64(data.ifi_ibytes)
                let tx = UInt64(data.ifi_obytes)
                received &+= rx
                sent &+= tx
                interfaces.append(RawCounter(name: name, received: rx, sent: tx))
                seen.insert(name)
            }
            cursor = item.ifa_next
        }
        return (received, sent, interfaces)
    }

    private func shouldCountInterface(_ name: String) -> Bool {
        // Physical/data-bearing interfaces only. VPN utun interfaces are intentionally
        // excluded so tunnelling does not make total usage count twice.
        name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("bridge")
    }

    private func identity(for interfaceName: String) -> (identifier: String, displayName: String, reliable: Bool) {
        if let wifi = wiFiIdentityByInterface[interfaceName] {
            return wifi
        }
        if interfaceName == currentPrimaryInterfaceName, !currentNetworkIdentifier.isEmpty {
            return (currentNetworkIdentifier, currentNetworkDisplayName, currentNetworkIdentityReliable)
        }
        let type = interfaceTypes[interfaceName]
        if type == .wifi { return ("wifi:interface:\(interfaceName)", "Wi-Fi (\(interfaceName))", false) }
        if type == .wiredEthernet { return ("ethernet:interface:\(interfaceName)", "Ethernet (\(interfaceName))", false) }
        if type == .cellular || interfaceName.hasPrefix("pdp_ip") { return ("cellular:interface:\(interfaceName)", "Cellular (\(interfaceName))", false) }
        if interfaceName.hasPrefix("bridge") { return ("bridge:interface:\(interfaceName)", "Bridge (\(interfaceName))", false) }
        return ("network:interface:\(interfaceName)", "Network (\(interfaceName))", false)
    }

    private func sample() {
        let counters = readCounters()
        let now = Date()
        let detailed = counters.interfaces.map { item -> NetworkInterfaceCounterSnapshot in
            let identity = identity(for: item.name)
            return NetworkInterfaceCounterSnapshot(interfaceName: item.name,
                                                   networkIdentifier: identity.identifier,
                                                   networkDisplayName: identity.displayName,
                                                   identityReliable: identity.reliable,
                                                   receivedBytes: item.received,
                                                   sentBytes: item.sent)
        }

        guard let previous = lastCounters, let previousDate = lastDate else {
            lastCounters = (counters.received, counters.sent)
            lastDate = now
            let identitySnapshot = (description: currentInterfaceDescription,
                                    identifier: currentNetworkIdentifier,
                                    displayName: currentNetworkDisplayName,
                                    reliable: currentNetworkIdentityReliable)
            Task { @MainActor [weak self] in
                guard let self else { return }
                snapshot.totalReceivedBytes = counters.received
                snapshot.totalSentBytes = counters.sent
                snapshot.interfaceDescription = identitySnapshot.description
                snapshot.networkIdentifier = identitySnapshot.identifier
                snapshot.networkDisplayName = identitySnapshot.displayName
                snapshot.networkIdentityReliable = identitySnapshot.reliable
                snapshot.interfaceCounters = detailed
            }
            return
        }

        let elapsed = max(now.timeIntervalSince(previousDate), 0.001)
        let rxDelta = counters.received >= previous.received ? counters.received - previous.received : 0
        let txDelta = counters.sent >= previous.sent ? counters.sent - previous.sent : 0
        let rx = UInt64(Double(rxDelta) / elapsed)
        let tx = UInt64(Double(txDelta) / elapsed)
        lastCounters = (counters.received, counters.sent)
        lastDate = now

        let identitySnapshot = (description: currentInterfaceDescription,
                                identifier: currentNetworkIdentifier,
                                displayName: currentNetworkDisplayName,
                                reliable: currentNetworkIdentityReliable)
        Task { @MainActor [weak self] in
            guard let self else { return }
            snapshot = NetworkSnapshot(downloadBytesPerSecond: rx,
                                       uploadBytesPerSecond: tx,
                                       totalReceivedBytes: counters.received,
                                       totalSentBytes: counters.sent,
                                       interfaceDescription: identitySnapshot.description,
                                       networkIdentifier: identitySnapshot.identifier,
                                       networkDisplayName: identitySnapshot.displayName,
                                       networkIdentityReliable: identitySnapshot.reliable,
                                       interfaceCounters: detailed)
        }
    }
}
