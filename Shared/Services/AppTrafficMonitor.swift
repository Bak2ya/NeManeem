import AppKit
import Foundation
import Security
import OSLog

/// Exact per-app traffic monitor backed only by NeManeem's Network System Extension.
/// No alternate process-scraping, private-API, or fallback measurement path is used.
@MainActor
final class AppTrafficMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "com.bak2ya.NeManeem", category: "TrafficXPC")
    enum Demand: Hashable { case menuBarInternet, popover, monitorWindow, settingsStatusWindow, settingsNetwork, troubleshooting, recording }

    @Published private(set) var usages: [AppNetworkUsage] = []
    /// Every process/app identity NeManeem has observed on this Mac. Unlike the live
    /// `usages` list, this catalog is intentionally stable so Network Control does
    /// not reshuffle or lose entries when traffic goes idle.
    @Published private(set) var observedUsages: [AppNetworkUsage] = []
    @Published private(set) var isRunning = false
    @Published private(set) var hasCompletedInitialSample = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasPersistentConnectionError = false
    @Published private(set) var connectionFailureCount = 0
    @Published private(set) var supportsProcessHierarchy = false

    private struct WireSnapshot: Decodable {
        struct Entry: Decodable {
            let identifier: String
            let processIdentifier: String?
            let inboundBytes: UInt64
            let outboundBytes: UInt64
            let localInboundBytes: UInt64
            let localOutboundBytes: UInt64
            let unknownInboundBytes: UInt64
            let unknownOutboundBytes: UInt64
            let lastActivity: TimeInterval
        }
        let schemaVersion: Int?
        let generatedAt: TimeInterval
        let engineStartedAt: TimeInterval
        let entries: [Entry]
    }

    private struct Counter {
        let inbound: UInt64
        let outbound: UInt64
        let localInbound: UInt64
        let localOutbound: UInt64
        let unknownInbound: UInt64
        let unknownOutbound: UInt64
    }

    private struct ProcessIdentity {
        let key: String
        let displayName: String
        let bundleIdentifier: String?
        let processIdentifier: String?
        let appDisplayName: String?
        let icon: NSImage
        let isSystemProcess: Bool
        let isAppleApp: Bool

        init(key: String,
             displayName: String,
             bundleIdentifier: String?,
             processIdentifier: String? = nil,
             appDisplayName: String? = nil,
             icon: NSImage,
             isSystemProcess: Bool,
             isAppleApp: Bool) {
            self.key = key
            self.displayName = displayName
            self.bundleIdentifier = bundleIdentifier
            self.processIdentifier = processIdentifier
            self.appDisplayName = appDisplayName
            self.icon = icon
            self.isSystemProcess = isSystemProcess
            self.isAppleApp = isAppleApp
        }
    }

    /// Minimal, local-only metadata for the stable Network Control catalog.
    /// No file path, traffic history, URL, domain, endpoint, or packet data is stored.
    private struct ObservedCatalogEntry: Codable {
        let identifier: String
        var displayName: String
        var bundleIdentifier: String?
        var processIdentifier: String?
        var appDisplayName: String?
        var isSystemProcess: Bool
        var isAppleApp: Bool
    }

    private struct TrackedUsage {
        let identity: ProcessIdentity
        var download: UInt64
        var upload: UInt64
        var localDownload: UInt64
        var localUpload: UInt64
        var unknownDownload: UInt64
        var unknownUpload: UInt64
        var cumulativeDownload: UInt64
        var cumulativeUpload: UInt64
        var cumulativeLocalDownload: UInt64
        var cumulativeLocalUpload: UInt64
        var cumulativeUnknownDownload: UInt64
        var cumulativeUnknownUpload: UInt64
        var lastActiveAt: Date
    }

    private var demands = Set<Demand>()
    private var removalInProgress = false
    private var resourceMode: ResourceMode = .balanced
    private var configuredMenuBarInterval: Double = 3.0
    private var configuredPopoverInterval: Double = 3.0
    private var configuredMonitorInterval: Double = 3.0
    private var pollingTimer: Timer?
    private var bootstrapWorkItem: DispatchWorkItem?
    private var connectionRetryWorkItem: DispatchWorkItem?
    private var currentPollingInterval: Double = 3.0
    private var pollInFlight = false
    private var pollToken: UUID?
    private var connectionFailureStartedAt: Date?
    private var consecutiveConnectionFailures = 0

    private var xpcConnection: NSXPCConnection?
    private var previousCounters: [String: Counter] = [:]
    private var previousGeneratedAt: TimeInterval?
    private var previousEngineStartedAt: TimeInterval?
    private var tracked: [String: TrackedUsage] = [:]
    private var identityCache: [String: ProcessIdentity] = [:]
    // Used only for anonymous exact counter delivery while Austerity needs
    // Internet/local classification for Data Limit. No bundle lookup or icon
    // resolution is performed on that background-only path.
    private let anonymousAusterityIcon = NSImage(size: NSSize(width: 1, height: 1))
    private let observedProcessIDsDefaultsKey = "network.observedProcessIDs" // legacy migration key
    private let observedCatalogDefaultsKey = "network.observedCatalogV1"
    private var observedProcessIDs: Set<String> = []
    private var observedCatalog: [String: ObservedCatalogEntry] = [:]
    private var observedCatalogHydrated = false
    private var observedCatalogEnrichmentStarted = false
    private var observedCatalogEnrichmentTask: Task<Void, Never>?
    private var observedCatalogEnrichmentID: UUID?
    private lazy var fallbackApplicationIcon: NSImage = Self.compactIcon(NSWorkspace.shared.icon(for: .application))

    init() {
        // Build 50 launch rule: the menu-bar surface must not wait for historical
        // app-catalog hydration. Persistent catalog data is loaded after the UI is
        // visible, and expensive app/icon/signature enrichment is incremental.
    }

    func hydrateObservedCatalogAfterLaunch() {
        guard !observedCatalogHydrated else { return }
        observedCatalogHydrated = true
        let defaults = UserDefaults.standard
        observedProcessIDs.formUnion(defaults.stringArray(forKey: observedProcessIDsDefaultsKey) ?? [])
        observedProcessIDs = observedProcessIDs.filter { !Self.isKnownTransportRelayIdentifier($0) }
        let loaded = Self.loadObservedCatalog()
        for (key, value) in loaded where observedCatalog[key] == nil && !Self.isKnownTransportRelayIdentifier(key) {
            observedCatalog[key] = value
        }
        // v0.5.10 may have persisted `unicornprod` as a normal app. Clean that stale
        // transport-only row once so it does not remain visible at 0 B/s forever.
        defaults.set(observedProcessIDs.sorted(), forKey: observedProcessIDsDefaultsKey)
        persistObservedCatalog()
        rebuildObservedUsages(resolveMissingIdentity: false)
        Self.logger.info("Deferred observed catalog loaded count=\(self.observedCatalog.count, privacy: .public)")
    }

    func enrichObservedCatalogMetadataIncrementally() {
        hydrateObservedCatalogAfterLaunch()
        guard !observedCatalogEnrichmentStarted, observedCatalogEnrichmentTask == nil else { return }
        observedCatalogEnrichmentStarted = true
        let identifiers = Array(observedProcessIDs.union(observedCatalog.keys))
        let enrichmentID = UUID()
        observedCatalogEnrichmentID = enrichmentID
        observedCatalogEnrichmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // A cancelled task may finish after a new enrichment task has already
                // started. Only clear bookkeeping when this is still the active task.
                if self.observedCatalogEnrichmentID == enrichmentID {
                    self.observedCatalogEnrichmentStarted = false
                    self.observedCatalogEnrichmentTask = nil
                    self.observedCatalogEnrichmentID = nil
                }
            }
            for identifier in identifiers {
                guard !Task.isCancelled, self.resourceMode != .austerity else { return }
                _ = self.resolveIdentity(identifier: identifier)
                if let saved = self.observedCatalog[identifier], let resolved = self.identityCache[identifier] {
                    self.observedCatalog[identifier] = ObservedCatalogEntry(identifier: identifier,
                                                                            displayName: saved.displayName.isEmpty ? resolved.displayName : saved.displayName,
                                                                            bundleIdentifier: saved.bundleIdentifier ?? resolved.bundleIdentifier,
                                                                            processIdentifier: saved.processIdentifier ?? resolved.processIdentifier,
                                                                            appDisplayName: saved.appDisplayName ?? resolved.appDisplayName,
                                                                            isSystemProcess: saved.isSystemProcess || resolved.isSystemProcess,
                                                                            isAppleApp: saved.isAppleApp || resolved.isAppleApp)
                }
                self.rebuildObservedUsages(resolveMissingIdentity: false)
                await Task.yield()
            }
        }
    }

    func clearTemporaryCaches() {
        observedCatalogEnrichmentTask?.cancel()
        observedCatalogEnrichmentTask = nil
        observedCatalogEnrichmentID = nil
        observedCatalogEnrichmentStarted = false
        identityCache.removeAll(keepingCapacity: false)
        if resourceMode == .austerity {
            observedUsages = []
        } else {
            // Keep the stable catalog available, but release resolved icon objects.
            // The list is rebuilt with one shared lightweight fallback icon and is
            // enriched again only when a user opens a feature that needs it.
            rebuildObservedUsages(resolveMissingIdentity: false)
        }
    }

    func setDemand(_ demand: Demand, active: Bool) {
        guard !removalInProgress else { return }
        if active { demands.insert(demand) } else { demands.remove(demand) }
        reconcile()
    }

    /// Stops exact app-traffic polling for the remainder of the current process.
    /// Safe removal uses this before tearing down the Network/System Extension so
    /// UI demand changes cannot reopen XPC while the extension is being removed.
    func prepareForRemoval() {
        removalInProgress = true
        demands.removeAll()
        observedCatalogEnrichmentTask?.cancel()
        observedCatalogEnrichmentTask = nil
        observedCatalogEnrichmentID = nil
        observedCatalogEnrichmentStarted = false
        stopPolling(resetUsages: true)
    }

    func setResourceMode(_ mode: ResourceMode) {
        guard resourceMode != mode else { return }
        resourceMode = mode
        if mode == .austerity || mode == .saver {
            observedCatalogEnrichmentTask?.cancel()
            observedCatalogEnrichmentTask = nil
            observedCatalogEnrichmentID = nil
            observedCatalogEnrichmentStarted = false
            identityCache.removeAll(keepingCapacity: false)
        }
        // A mode transition may switch between anonymous counter delivery and
        // user-facing identity-rich rows. Reset only the live sampling baseline so
        // the first sample in the new mode establishes a truthful fresh baseline.
        previousCounters.removeAll(keepingCapacity: false)
        previousGeneratedAt = nil
        tracked.removeAll(keepingCapacity: false)
        usages = []
        if mode == .austerity {
            // Austerity has no app list. Release the stable UI rows and their image
            // references immediately; lightweight persisted catalog metadata stays.
            observedUsages = []
        } else if mode == .saver {
            rebuildObservedUsages(resolveMissingIdentity: false)
        } else if observedUsages.isEmpty && observedCatalogHydrated {
            rebuildObservedUsages(resolveMissingIdentity: false)
        }
        hasCompletedInitialSample = false
        reconcile()
    }

    private var effectiveDemands: Set<Demand> {
        guard resourceMode == .austerity else { return demands }
        // Extreme saver mode removes app-by-app presentation work. Explicit network
        // settings/troubleshooting and anonymous data-limit classification may still
        // request the exact source counters when they are genuinely needed.
        return demands.filter { demand in
            switch demand {
            case .popover, .monitorWindow, .settingsStatusWindow:
                return false
            case .menuBarInternet, .settingsNetwork, .troubleshooting, .recording:
                return true
            }
        }
    }

    func setConfiguredIntervals(menuBar: Double, popover: Double, monitor: Double) {
        configuredMenuBarInterval = SettingsStore.normalizeInterval(menuBar)
        configuredPopoverInterval = SettingsStore.normalizeInterval(popover)
        configuredMonitorInterval = SettingsStore.normalizeInterval(monitor)
        reconcile()
    }

    private func desiredSampleInterval() -> Double {
        let active = effectiveDemands
        var intervals: [Double] = []
        if active.contains(.menuBarInternet) { intervals.append(configuredMenuBarInterval) }
        if active.contains(.popover) { intervals.append(configuredPopoverInterval) }
        if active.contains(.monitorWindow) { intervals.append(configuredMonitorInterval) }
        if active.contains(.settingsStatusWindow) { intervals.append(configuredPopoverInterval) }
        if active.contains(.settingsNetwork) || active.contains(.troubleshooting) || active.contains(.recording) { intervals.append(1.0) }
        return intervals.min() ?? 1.0
    }

    private func reconcile() {
        guard !effectiveDemands.isEmpty else {
            stopPolling()
            return
        }

        let desired = desiredSampleInterval()
        if !isRunning || abs(currentPollingInterval - desired) > 0.001 {
            startPolling(interval: desired)
        }
    }

    private func startPolling(interval: Double) {
        stopPolling(resetUsages: true)
        currentPollingInterval = SettingsStore.normalizeInterval(interval)
        isRunning = true
        Self.logger.notice("App traffic polling started interval=\(self.currentPollingInterval, privacy: .public)s")
        errorMessage = nil
        hasPersistentConnectionError = false
        connectionFailureStartedAt = nil
        consecutiveConnectionFailures = 0
        connectionFailureCount = 0
        hasCompletedInitialSample = false

        pollNow()

        // Establish a quick second sample so a 10-second presentation interval does
        // not leave the popover saying "checking" for 10 seconds on first open.
        let bootstrap = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.pollNow() }
        }
        bootstrapWorkItem = bootstrap
        DispatchQueue.main.asyncAfter(deadline: .now() + min(0.5, currentPollingInterval), execute: bootstrap)

        startRegularPollingTimer()
    }

    private func startRegularPollingTimer() {
        guard isRunning, pollingTimer == nil else { return }
        let timer = Timer(timeInterval: currentPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollNow() }
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pauseRegularPollingForReconnect() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        bootstrapWorkItem?.cancel()
        bootstrapWorkItem = nil
    }

    private func stopPolling(resetUsages: Bool = true) {
        pollingTimer?.invalidate()
        pollingTimer = nil
        bootstrapWorkItem?.cancel()
        bootstrapWorkItem = nil
        connectionRetryWorkItem?.cancel()
        connectionRetryWorkItem = nil
        pollInFlight = false
        pollToken = nil
        isRunning = false
        hasCompletedInitialSample = false
        errorMessage = nil
        hasPersistentConnectionError = false
        connectionFailureStartedAt = nil
        consecutiveConnectionFailures = 0
        connectionFailureCount = 0
        previousCounters = [:]
        previousGeneratedAt = nil
        previousEngineStartedAt = nil
        tracked = [:]
        identityCache = [:]
        if resetUsages {
            usages = []
            rebuildObservedUsages()
        }
        invalidateConnection()
    }

    private func pollNow() {
        guard isRunning, !pollInFlight else { return }
        pollInFlight = true
        let token = UUID()
        pollToken = token

        let connection = ensureConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.finishPoll(token: token, result: .failure(error)) }
        }

        guard let remote = proxy as? NeManeemTrafficXPCProtocol else {
            let error = NSError(domain: "NeManeemTrafficXPC", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Network Extension IPC proxy is unavailable."])
            finishPoll(token: token, result: .failure(error))
            return
        }

        remote.fetchTrafficSnapshot { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                do {
                    let snapshot = try JSONDecoder().decode(WireSnapshot.self, from: data)
                    self.finishPoll(token: token, result: .success(snapshot))
                } catch {
                    self.finishPoll(token: token, result: .failure(error))
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.pollToken == token else { return }
            let error = NSError(domain: "NeManeemTrafficXPC", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Network Extension did not respond in time."])
            self.finishPoll(token: token, result: .failure(error))
        }
    }

    private func finishPoll(token: UUID, result: Result<WireSnapshot, Error>) {
        guard pollToken == token else { return }
        pollToken = nil
        pollInFlight = false

        switch result {
        case .success(let snapshot):
            let recovered = consecutiveConnectionFailures > 0
            errorMessage = nil
            hasPersistentConnectionError = false
            connectionFailureStartedAt = nil
            consecutiveConnectionFailures = 0
            connectionFailureCount = 0
            connectionRetryWorkItem?.cancel()
            connectionRetryWorkItem = nil
            if recovered { Self.logger.notice("XPC connection recovered") }
            consume(snapshot)
            startRegularPollingTimer()
            if !hasCompletedInitialSample { scheduleConnectionRetry(after: min(0.25, currentPollingInterval)) }
        case .failure(let error):
            handleConnectionFailure(error)
        }
    }

    private func handleConnectionFailure(_ error: Error) {
        invalidateConnection()
        pauseRegularPollingForReconnect()
        let nsError = error as NSError
        // Keep diagnostics technical and privacy-minimal: no URL, domain visited,
        // remote endpoint, packet payload, process traffic, or browsing information.
        errorMessage = "\(nsError.domain):\(nsError.code)"
        consecutiveConnectionFailures += 1
        connectionFailureCount = consecutiveConnectionFailures
        if connectionFailureStartedAt == nil { connectionFailureStartedAt = Date() }
        let elapsed = Date().timeIntervalSince(connectionFailureStartedAt ?? Date())
        hasPersistentConnectionError = elapsed >= 12
        let delay = reconnectDelay(forFailureCount: consecutiveConnectionFailures)
        Self.logger.error("XPC poll failed errorDomain=\(nsError.domain, privacy: .public) code=\(nsError.code) attempt=\(self.consecutiveConnectionFailures, privacy: .public) nextRetry=\(delay, privacy: .public)s")
        scheduleConnectionRetry(after: delay)
    }

    private func reconnectDelay(forFailureCount count: Int) -> TimeInterval {
        // Fast enough to recover during normal system-extension startup, then back
        // off aggressively so a persistent failure does not keep waking a MacBook.
        switch count {
        case ...1: return 0.5
        case 2: return 1.0
        case 3: return 2.0
        case 4: return 4.0
        case 5: return 8.0
        case 6: return 15.0
        default: return 30.0
        }
    }

    private func scheduleConnectionRetry(after delay: TimeInterval) {
        guard isRunning else { return }
        connectionRetryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.pollNow() }
        }
        connectionRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func ensureConnection() -> NSXPCConnection {
        if let xpcConnection { return xpcConnection }
        let serviceName = Self.resolvedTrafficMachServiceName()
        Self.logger.notice("Opening Network Extension XPC service=\(serviceName, privacy: .public)")
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: NeManeemTrafficXPCProtocol.self)
        if let requirement = Self.peerCodeSigningRequirement(bundleIdentifier: AppConstants.filterBundleIdentifier) {
            Self.logger.notice("Applying XPC peer signing requirement for Filter")
            connection.setCodeSigningRequirement(requirement)
        } else {
            Self.logger.error("Could not construct XPC peer signing requirement because the host Team ID was unavailable")
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            Self.logger.error("Network Extension XPC connection invalidated")
            Task { @MainActor in
                guard let self else { return }
                if self.xpcConnection === connection { self.xpcConnection = nil }
            }
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            Self.logger.error("Network Extension XPC connection interrupted")
            Task { @MainActor in
                guard let self else { return }
                if self.xpcConnection === connection { self.xpcConnection = nil }
            }
        }
        connection.resume()
        xpcConnection = connection
        return connection
    }

    private func invalidateConnection() {
        xpcConnection?.invalidate()
        xpcConnection = nil
    }

    private static func peerCodeSigningRequirement(bundleIdentifier: String) -> String? {
        guard let teamIdentifier = ownTeamIdentifier() else { return nil }
        return #"identifier "\#(bundleIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
    }

    private static func resolvedTrafficMachServiceName() -> String {
        let configured = AppConstants.trafficMachServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty, !configured.contains("$(") { return configured }
        // The service lives inside the shared App Group namespace. Keep this
        // deterministic and independent of any individual developer Team ID.
        return "\(AppConstants.applicationGroupIdentifier).traffic"
    }

    private static func ownTeamIdentifier() -> String? {
        var runningCode: SecCode?
        if SecCodeCopySelf([], &runningCode) == errSecSuccess, let runningCode {
            // SecCodeCopySigningInformation expects SecStaticCode in the Swift SDK.
            // Convert the running SecCode first instead of passing SecCode directly.
            var runningStaticCode: SecStaticCode?
            if SecCodeCopyStaticCode(runningCode, [], &runningStaticCode) == errSecSuccess,
               let runningStaticCode {
                var infoRef: CFDictionary?
                if SecCodeCopySigningInformation(runningStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
                   let info = infoRef as? [CFString: Any],
                   let team = info[kSecCodeInfoTeamIdentifier] as? String,
                   !team.isEmpty {
                    return team
                }
            }
        }

        let codeURL = Bundle.main.bundleURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(codeURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [CFString: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier] as? String
    }

    private static func wireEntryKey(_ entry: WireSnapshot.Entry) -> String {
        let processIdentifier = entry.processIdentifier ?? entry.identifier
        return processIdentifier == entry.identifier
            ? entry.identifier
            : "\(entry.identifier)|\(processIdentifier)"
    }

    /// Transport daemons can carry traffic on behalf of many source apps. Showing
    /// those tunnel bytes as if the daemon itself consumed them is misleading and
    /// double-counts traffic once the source-app flow is live-metered. Keep this list
    /// intentionally narrow and evidence-based; v0.5.13 adds only Unicorn Pro's
    /// verified `unicornprod` helper.
    private static func isKnownTransportRelayIdentifier(_ identifier: String) -> Bool {
        let components = identifier.lowercased().split(separator: "|")
        return components.contains { value in
            value == "unicornprod" || value.hasSuffix(".unicornprod")
        }
    }

    private static func isKnownTransportRelayEntry(_ entry: WireSnapshot.Entry) -> Bool {
        isKnownTransportRelayIdentifier(entry.identifier) ||
            isKnownTransportRelayIdentifier(entry.processIdentifier ?? "")
    }

    private func consume(_ snapshot: WireSnapshot) {
        let schemaVersion = snapshot.schemaVersion ?? 1
        supportsProcessHierarchy = schemaVersion >= AppConstants.processHierarchySchemaVersion
        if supportsProcessHierarchy {
            UserDefaults.standard.set(schemaVersion, forKey: AppConstants.extensionActiveSchemaDefaultsKey)
        }
        if previousEngineStartedAt != nil,
           let previousEngineStartedAt,
           abs(previousEngineStartedAt - snapshot.engineStartedAt) > 0.001 {
            previousCounters = [:]
            previousGeneratedAt = nil
            tracked = [:]
            hasCompletedInitialSample = false
        }
        previousEngineStartedAt = snapshot.engineStartedAt

        // Hide known VPN transport daemons even while macOS is briefly serving a
        // snapshot from an older active extension during replacement. Their outer
        // tunnel bytes are not user-app usage.
        let visibleEntries = snapshot.entries.filter { !Self.isKnownTransportRelayEntry($0) }

        // Build 42 snapshots may contain multiple child-process entries for one
        // owning app, so every live counter is keyed by app+process identity.
        var current: [String: Counter] = [:]
        for entry in visibleEntries {
            let key = Self.wireEntryKey(entry)
            current[key] = Counter(inbound: entry.inboundBytes,
                                   outbound: entry.outboundBytes,
                                   localInbound: entry.localInboundBytes,
                                   localOutbound: entry.localOutboundBytes,
                                   unknownInbound: entry.unknownInboundBytes,
                                   unknownOutbound: entry.unknownOutboundBytes)
        }

        // In Austerity, if the only reason to request source-app counters is the
        // Internet-only Data Limit, deliver exact anonymous counters without doing
        // bundle/signature/icon/catalog work. Opening Network settings or
        // Troubleshooting explicitly leaves this path and restores full identities.
        if resourceMode == .austerity,
           !effectiveDemands.isEmpty,
           effectiveDemands.isSubset(of: [.recording, .menuBarInternet]) {
            consumeAnonymousAusteritySnapshot(snapshot, entries: visibleEntries, current: current)
            return
        }

        guard let previousTime = previousGeneratedAt else {
            let now = Date()
            previousCounters = current
            previousGeneratedAt = snapshot.generatedAt
            let keys = visibleEntries.map(Self.wireEntryKey)
            rememberObservedProcessIDs(keys)
            for entry in visibleEntries {
                let key = Self.wireEntryKey(entry)
                let processIdentifier = entry.processIdentifier ?? entry.identifier
                let identity = resolveIdentity(appIdentifier: entry.identifier,
                                               processIdentifier: processIdentifier)
                rememberObservedIdentity(identity)
                let activeDate = entry.lastActivity > 0 ? Date(timeIntervalSince1970: entry.lastActivity) : now
                tracked[key] = TrackedUsage(identity: identity,
                                            download: 0,
                                            upload: 0,
                                            localDownload: 0,
                                            localUpload: 0,
                                            unknownDownload: 0,
                                            unknownUpload: 0,
                                            cumulativeDownload: entry.inboundBytes,
                                            cumulativeUpload: entry.outboundBytes,
                                            cumulativeLocalDownload: entry.localInboundBytes,
                                            cumulativeLocalUpload: entry.localOutboundBytes,
                                            cumulativeUnknownDownload: entry.unknownInboundBytes,
                                            cumulativeUnknownUpload: entry.unknownOutboundBytes,
                                            lastActiveAt: activeDate)
            }
            publishTrackedUsages()
            rebuildObservedUsages()
            return
        }

        let elapsed = max(0.05, snapshot.generatedAt - previousTime)
        previousGeneratedAt = snapshot.generatedAt
        let now = Date()
        var seen = Set<String>()
        rememberObservedProcessIDs(visibleEntries.map(Self.wireEntryKey))

        for entry in visibleEntries {
            let key = Self.wireEntryKey(entry)
            seen.insert(key)
            let previous = previousCounters[key] ?? Counter(inbound: 0, outbound: 0, localInbound: 0, localOutbound: 0, unknownInbound: 0, unknownOutbound: 0)
            let deltaInbound = entry.inboundBytes >= previous.inbound ? entry.inboundBytes - previous.inbound : 0
            let deltaOutbound = entry.outboundBytes >= previous.outbound ? entry.outboundBytes - previous.outbound : 0
            let deltaLocalInbound = entry.localInboundBytes >= previous.localInbound ? entry.localInboundBytes - previous.localInbound : 0
            let deltaLocalOutbound = entry.localOutboundBytes >= previous.localOutbound ? entry.localOutboundBytes - previous.localOutbound : 0
            let deltaUnknownInbound = entry.unknownInboundBytes >= previous.unknownInbound ? entry.unknownInboundBytes - previous.unknownInbound : 0
            let deltaUnknownOutbound = entry.unknownOutboundBytes >= previous.unknownOutbound ? entry.unknownOutboundBytes - previous.unknownOutbound : 0
            let download = UInt64((Double(deltaInbound) / elapsed).rounded())
            let upload = UInt64((Double(deltaOutbound) / elapsed).rounded())
            let localDownload = UInt64((Double(deltaLocalInbound) / elapsed).rounded())
            let localUpload = UInt64((Double(deltaLocalOutbound) / elapsed).rounded())
            let unknownDownload = UInt64((Double(deltaUnknownInbound) / elapsed).rounded())
            let unknownUpload = UInt64((Double(deltaUnknownOutbound) / elapsed).rounded())
            let processIdentifier = entry.processIdentifier ?? entry.identifier
            let identity = resolveIdentity(appIdentifier: entry.identifier,
                                           processIdentifier: processIdentifier)
            rememberObservedIdentity(identity)
            let activeDate = entry.lastActivity > 0 ? Date(timeIntervalSince1970: entry.lastActivity) : now

            tracked[key] = TrackedUsage(identity: identity,
                                        download: download,
                                        upload: upload,
                                        localDownload: localDownload,
                                        localUpload: localUpload,
                                        unknownDownload: unknownDownload,
                                        unknownUpload: unknownUpload,
                                        cumulativeDownload: entry.inboundBytes,
                                        cumulativeUpload: entry.outboundBytes,
                                        cumulativeLocalDownload: entry.localInboundBytes,
                                        cumulativeLocalUpload: entry.localOutboundBytes,
                                        cumulativeUnknownDownload: entry.unknownInboundBytes,
                                        cumulativeUnknownUpload: entry.unknownOutboundBytes,
                                        lastActiveAt: activeDate)
        }

        for key in tracked.keys where !seen.contains(key) {
            guard var value = tracked[key] else { continue }
            value.download = 0
            value.upload = 0
            value.localDownload = 0
            value.localUpload = 0
            value.unknownDownload = 0
            value.unknownUpload = 0
            tracked[key] = value
        }

        previousCounters = current

        if tracked.count > 400 {
            let removeCount = tracked.count - 320
            // `tracked` is keyed by the raw wire identity. A verified broker may
            // intentionally publish under an owning-app identity instead, so prune
            // by the dictionary key rather than the remapped identity key.
            let oldestKeys = tracked.sorted { $0.value.lastActiveAt < $1.value.lastActiveAt }
                .prefix(removeCount)
                .map(\.key)
            for key in oldestKeys { tracked.removeValue(forKey: key) }
        }

        publishTrackedUsages()
        rebuildObservedUsages()
        hasCompletedInitialSample = true
    }

    private func consumeAnonymousAusteritySnapshot(_ snapshot: WireSnapshot, entries: [WireSnapshot.Entry], current: [String: Counter]) {
        let previousTime = previousGeneratedAt
        let elapsed = max(0.05, snapshot.generatedAt - (previousTime ?? snapshot.generatedAt))
        let now = Date()

        usages = entries.map { entry in
            let key = Self.wireEntryKey(entry)
            let previous = previousCounters[key]
            let deltaInbound = previous.map { entry.inboundBytes >= $0.inbound ? entry.inboundBytes - $0.inbound : 0 } ?? 0
            let deltaOutbound = previous.map { entry.outboundBytes >= $0.outbound ? entry.outboundBytes - $0.outbound : 0 } ?? 0
            let deltaLocalInbound = previous.map { entry.localInboundBytes >= $0.localInbound ? entry.localInboundBytes - $0.localInbound : 0 } ?? 0
            let deltaLocalOutbound = previous.map { entry.localOutboundBytes >= $0.localOutbound ? entry.localOutboundBytes - $0.localOutbound : 0 } ?? 0
            let deltaUnknownInbound = previous.map { entry.unknownInboundBytes >= $0.unknownInbound ? entry.unknownInboundBytes - $0.unknownInbound : 0 } ?? 0
            let deltaUnknownOutbound = previous.map { entry.unknownOutboundBytes >= $0.unknownOutbound ? entry.unknownOutboundBytes - $0.unknownOutbound : 0 } ?? 0
            let processIdentifier = entry.processIdentifier ?? entry.identifier
            let activeDate = entry.lastActivity > 0 ? Date(timeIntervalSince1970: entry.lastActivity) : now

            return AppNetworkUsage(
                id: key,
                displayName: entry.identifier,
                bundleIdentifier: entry.identifier,
                processIdentifier: processIdentifier,
                appDisplayName: nil,
                icon: anonymousAusterityIcon,
                isSystemProcess: false,
                isAppleApp: false,
                downloadBytesPerSecond: previousTime == nil ? 0 : UInt64((Double(deltaInbound) / elapsed).rounded()),
                uploadBytesPerSecond: previousTime == nil ? 0 : UInt64((Double(deltaOutbound) / elapsed).rounded()),
                localDownloadBytesPerSecond: previousTime == nil ? 0 : UInt64((Double(deltaLocalInbound) / elapsed).rounded()),
                localUploadBytesPerSecond: previousTime == nil ? 0 : UInt64((Double(deltaLocalOutbound) / elapsed).rounded()),
                unknownDownloadBytesPerSecond: previousTime == nil ? 0 : UInt64((Double(deltaUnknownInbound) / elapsed).rounded()),
                unknownUploadBytesPerSecond: previousTime == nil ? 0 : UInt64((Double(deltaUnknownOutbound) / elapsed).rounded()),
                cumulativeDownloadBytes: entry.inboundBytes,
                cumulativeUploadBytes: entry.outboundBytes,
                cumulativeLocalDownloadBytes: entry.localInboundBytes,
                cumulativeLocalUploadBytes: entry.localOutboundBytes,
                cumulativeUnknownDownloadBytes: entry.unknownInboundBytes,
                cumulativeUnknownUploadBytes: entry.unknownOutboundBytes,
                lastActiveAt: activeDate
            )
        }

        previousCounters = current
        previousGeneratedAt = snapshot.generatedAt
        hasCompletedInitialSample = true
    }

    func refreshCompatibilityPresentation() {
        publishTrackedUsages()
        rebuildObservedUsages()
    }

    private func publishTrackedUsages() {
        let groupingEnabled = UserDefaults.standard.bool(forKey: AppConstants.safariNetworkServiceGroupingDefaultsKey)
        usages = tracked.values.map {
            AppNetworkUsage(id: $0.identity.key,
                            displayName: $0.identity.displayName,
                            bundleIdentifier: $0.identity.bundleIdentifier,
                            processIdentifier: $0.identity.processIdentifier,
                            appDisplayName: $0.identity.appDisplayName,
                            icon: $0.identity.icon,
                            isSystemProcess: $0.identity.isSystemProcess,
                            isAppleApp: $0.identity.isAppleApp,
                            downloadBytesPerSecond: $0.download,
                            uploadBytesPerSecond: $0.upload,
                            localDownloadBytesPerSecond: $0.localDownload,
                            localUploadBytesPerSecond: $0.localUpload,
                            unknownDownloadBytesPerSecond: $0.unknownDownload,
                            unknownUploadBytesPerSecond: $0.unknownUpload,
                            cumulativeDownloadBytes: $0.cumulativeDownload,
                            cumulativeUploadBytes: $0.cumulativeUpload,
                            cumulativeLocalDownloadBytes: $0.cumulativeLocalDownload,
                            cumulativeLocalUploadBytes: $0.cumulativeLocalUpload,
                            cumulativeUnknownDownloadBytes: $0.cumulativeUnknownDownload,
                            cumulativeUnknownUploadBytes: $0.cumulativeUnknownUpload,
                            lastActiveAt: $0.lastActiveAt)
        }.map { compatibilityMappedUsage($0, safariGroupingEnabled: groupingEnabled) }.sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            if $0.totalBytesPerSecond == $1.totalBytesPerSecond {
                return ($0.appDisplayName ?? $0.displayName).localizedCaseInsensitiveCompare($1.appDisplayName ?? $1.displayName) == .orderedAscending
            }
            return $0.totalBytesPerSecond > $1.totalBytesPerSecond
        }
    }

    private func rememberObservedProcessIDs(_ identifiers: [String]) {
        let visibleIdentifiers = identifiers.filter { !Self.isKnownTransportRelayIdentifier($0) }
        let oldCount = observedProcessIDs.count
        observedProcessIDs.formUnion(visibleIdentifiers)
        guard observedProcessIDs.count != oldCount else { return }
        UserDefaults.standard.set(observedProcessIDs.sorted(), forKey: observedProcessIDsDefaultsKey)
    }

    private func rememberObservedIdentity(_ identity: ProcessIdentity) {
        guard !Self.isKnownTransportRelayIdentifier(identity.key) else { return }

        // v0.5.13 could persist helper/XPC signing identifiers as standalone system
        // rows because the provider had not yet proven their outer owning .app. Once
        // schema 7 supplies an app+process hierarchy, remove only the exact stale
        // standalone process key. The child remains available inside the owning app
        // for expert drill-down, while ordinary UI shows the application itself.
        if let appIdentifier = identity.bundleIdentifier,
           let processIdentifier = identity.processIdentifier,
           appIdentifier != processIdentifier {
            let removedProcessID = observedProcessIDs.remove(processIdentifier) != nil
            let removedCatalogEntry = observedCatalog.removeValue(forKey: processIdentifier) != nil
            if removedProcessID {
                UserDefaults.standard.set(observedProcessIDs.sorted(), forKey: observedProcessIDsDefaultsKey)
            }
            if removedCatalogEntry { persistObservedCatalog() }
        }

        observedProcessIDs.insert(identity.key)
        let newEntry = ObservedCatalogEntry(identifier: identity.key,
                                            displayName: identity.displayName,
                                            bundleIdentifier: identity.bundleIdentifier,
                                            processIdentifier: identity.processIdentifier,
                                            appDisplayName: identity.appDisplayName,
                                            isSystemProcess: identity.isSystemProcess,
                                            isAppleApp: identity.isAppleApp)
        let old = observedCatalog[identity.key]
        let changed = old?.displayName != newEntry.displayName ||
            old?.bundleIdentifier != newEntry.bundleIdentifier ||
            old?.processIdentifier != newEntry.processIdentifier ||
            old?.appDisplayName != newEntry.appDisplayName ||
            old?.isSystemProcess != newEntry.isSystemProcess ||
            old?.isAppleApp != newEntry.isAppleApp
        observedCatalog[identity.key] = newEntry
        if changed { persistObservedCatalog() }
    }

    private func rebuildObservedUsages(resolveMissingIdentity: Bool = false) {
        let liveByID = Dictionary(uniqueKeysWithValues: usages.map { ($0.id, $0) })
        let identifiers = observedProcessIDs.union(observedCatalog.keys).filter { !Self.isKnownTransportRelayIdentifier($0) }
        let fallbackIcon = fallbackApplicationIcon
        let groupingEnabled = UserDefaults.standard.bool(forKey: AppConstants.safariNetworkServiceGroupingDefaultsKey)
        observedUsages = identifiers.map { identifier in
            if let live = liveByID[identifier] { return live }
            let saved = observedCatalog[identifier]
            let resolved = resolveMissingIdentity ? resolveIdentity(identifier: identifier) : identityCache[identifier]
            return AppNetworkUsage(id: resolved?.key ?? identifier,
                                   displayName: saved?.displayName ?? resolved?.displayName ?? identifier,
                                   bundleIdentifier: saved?.bundleIdentifier ?? resolved?.bundleIdentifier,
                                   processIdentifier: saved?.processIdentifier ?? resolved?.processIdentifier,
                                   appDisplayName: saved?.appDisplayName ?? resolved?.appDisplayName,
                                   icon: resolved?.icon ?? fallbackIcon,
                                   isSystemProcess: saved?.isSystemProcess ?? resolved?.isSystemProcess ?? false,
                                   isAppleApp: saved?.isAppleApp ?? resolved?.isAppleApp ?? false,
                                   downloadBytesPerSecond: 0,
                                   uploadBytesPerSecond: 0,
                                   cumulativeDownloadBytes: 0,
                                   cumulativeUploadBytes: 0,
                                   lastActiveAt: .distantPast)
        }.map { compatibilityMappedUsage($0, safariGroupingEnabled: groupingEnabled) }.sorted { lhs, rhs in
            (lhs.appDisplayName ?? lhs.displayName).localizedCaseInsensitiveCompare(rhs.appDisplayName ?? rhs.displayName) == .orderedAscending
        }
    }

    func clearObservedCatalog() {
        observedProcessIDs.removeAll()
        observedCatalog.removeAll()
        observedCatalogHydrated = true
        observedCatalogEnrichmentTask?.cancel()
        observedCatalogEnrichmentTask = nil
        observedCatalogEnrichmentID = nil
        observedCatalogEnrichmentStarted = false
        identityCache.removeAll()
        UserDefaults.standard.removeObject(forKey: observedProcessIDsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: observedCatalogDefaultsKey)
        rebuildObservedUsages()
    }

    private func persistObservedCatalog() {
        guard let data = try? JSONEncoder().encode(Array(observedCatalog.values)) else { return }
        UserDefaults.standard.set(data, forKey: observedCatalogDefaultsKey)
    }

    private static func loadObservedCatalog() -> [String: ObservedCatalogEntry] {
        guard let data = UserDefaults.standard.data(forKey: "network.observedCatalogV1"),
              let entries = try? JSONDecoder().decode([ObservedCatalogEntry].self, from: data) else { return [:] }
        // Treat duplicate identifiers as recoverable persisted-data noise rather than
        // trapping during launch/deferred hydration. The newest decoded entry wins.
        var result: [String: ObservedCatalogEntry] = [:]
        for entry in entries { result[entry.identifier] = entry }
        return result
    }

    private func compatibilityMappedUsage(_ usage: AppNetworkUsage, safariGroupingEnabled: Bool) -> AppNetworkUsage {
        guard safariGroupingEnabled, Self.isSafariNetworkServiceIdentifier(usage.id) || Self.isSafariNetworkServiceIdentifier(usage.processIdentifier) || Self.isSafariNetworkServiceIdentifier(usage.bundleIdentifier) else {
            return usage
        }
        let safari = resolveFlatIdentity(identifier: "com.apple.Safari")
        return AppNetworkUsage(id: usage.id,
                               displayName: "Safari Networking",
                               bundleIdentifier: "com.apple.Safari",
                               processIdentifier: usage.processIdentifier ?? usage.id,
                               appDisplayName: safari.displayName,
                               icon: safari.icon,
                               isSystemProcess: false,
                               isAppleApp: true,
                               downloadBytesPerSecond: usage.downloadBytesPerSecond,
                               uploadBytesPerSecond: usage.uploadBytesPerSecond,
                               localDownloadBytesPerSecond: usage.localDownloadBytesPerSecond,
                               localUploadBytesPerSecond: usage.localUploadBytesPerSecond,
                               unknownDownloadBytesPerSecond: usage.unknownDownloadBytesPerSecond,
                               unknownUploadBytesPerSecond: usage.unknownUploadBytesPerSecond,
                               cumulativeDownloadBytes: usage.cumulativeDownloadBytes,
                               cumulativeUploadBytes: usage.cumulativeUploadBytes,
                               cumulativeLocalDownloadBytes: usage.cumulativeLocalDownloadBytes,
                               cumulativeLocalUploadBytes: usage.cumulativeLocalUploadBytes,
                               cumulativeUnknownDownloadBytes: usage.cumulativeUnknownDownloadBytes,
                               cumulativeUnknownUploadBytes: usage.cumulativeUnknownUploadBytes,
                               lastActiveAt: usage.lastActiveAt)
    }

    private static func isSafariNetworkServiceIdentifier(_ identifier: String?) -> Bool {
        guard let value = identifier?.lowercased() else { return false }
        return value.contains("webkit.networking")
    }

    private func resolveIdentity(identifier: String) -> ProcessIdentity {
        if let cached = identityCache[identifier] { return cached }
        if let separator = identifier.firstIndex(of: "|") {
            let appIdentifier = String(identifier[..<separator])
            let processIdentifier = String(identifier[identifier.index(after: separator)...])
            return resolveIdentity(appIdentifier: appIdentifier, processIdentifier: processIdentifier)
        }
        return resolveFlatIdentity(identifier: identifier)
    }

    private func resolveIdentity(appIdentifier: String, processIdentifier: String) -> ProcessIdentity {
        let key = processIdentifier == appIdentifier ? appIdentifier : "\(appIdentifier)|\(processIdentifier)"
        if let cached = identityCache[key] { return cached }

        // Public-API-only policy: do not infer ownership of shared system brokers
        // such as com.apple.WebKit.Networking from process names or which browser is
        // currently running. If the audit-token/code-signing path cannot prove an
        // owning .app, keep the broker as a System Service rather than guessing.

        let app = resolveFlatIdentity(identifier: appIdentifier)
        if processIdentifier == appIdentifier {
            let value = ProcessIdentity(key: key,
                                        displayName: app.displayName,
                                        bundleIdentifier: app.bundleIdentifier,
                                        processIdentifier: processIdentifier,
                                        appDisplayName: app.displayName,
                                        icon: app.icon,
                                        isSystemProcess: app.isSystemProcess,
                                        isAppleApp: app.isAppleApp)
            identityCache[key] = value
            return value
        }

        let process = resolveFlatIdentity(identifier: processIdentifier)
        let value = ProcessIdentity(key: key,
                                    displayName: process.displayName,
                                    bundleIdentifier: app.bundleIdentifier ?? appIdentifier,
                                    processIdentifier: processIdentifier,
                                    appDisplayName: app.displayName,
                                    icon: app.icon,
                                    isSystemProcess: app.isSystemProcess,
                                    isAppleApp: app.isAppleApp)
        identityCache[key] = value
        return value
    }


    private func resolveFlatIdentity(identifier: String) -> ProcessIdentity {
        if let cached = identityCache[identifier] { return cached }

        if identifier == "__nemaneem.unidentified__" {
            let icon = fallbackApplicationIcon
            let value = ProcessIdentity(key: identifier,
                                        displayName: "Unidentified Process",
                                        bundleIdentifier: nil,
                                        processIdentifier: identifier,
                                        appDisplayName: nil,
                                        icon: icon,
                                        isSystemProcess: true,
                                        isAppleApp: false)
            identityCache[identifier] = value
            return value
        }

        var displayName = identifier.split(separator: ".").last.map(String.init) ?? identifier
        var icon = fallbackApplicationIcon
        var isSystemProcess = identifier.hasPrefix("com.apple.")
        var isAppleApp = false

        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == identifier }) {
            displayName = running.localizedName ?? displayName
            if let runningIcon = running.icon { icon = Self.compactIcon(runningIcon) }
            if let bundleURL = running.bundleURL {
                let path = bundleURL.path
                let isApplicationBundle = bundleURL.pathExtension.lowercased() == "app"
                isSystemProcess = identifier.hasPrefix("com.apple.") && path.hasPrefix("/System/") && !isApplicationBundle
                isAppleApp = isApplicationBundle && Self.isAppleSignedApplication(at: bundleURL)
            }
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            let bundle = Bundle(url: appURL)
            displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? displayName
            icon = Self.compactIcon(NSWorkspace.shared.icon(forFile: appURL.path))
            isSystemProcess = false
            isAppleApp = Self.isAppleSignedApplication(at: appURL)
        } else {
            isSystemProcess = identifier.hasPrefix("com.apple.") || Self.systemDaemonIdentifiers.contains(identifier.lowercased())
        }

        let value = ProcessIdentity(key: identifier,
                                    displayName: displayName,
                                    bundleIdentifier: identifier,
                                    processIdentifier: identifier,
                                    appDisplayName: displayName,
                                    icon: icon,
                                    isSystemProcess: isSystemProcess,
                                    isAppleApp: isAppleApp)
        identityCache[identifier] = value
        return value
    }


    /// NSWorkspace application icons can carry large multi-resolution image reps.
    /// The status UI only needs a 32 pt icon, so render a compact standalone bitmap
    /// before caching it. Changing NSImage.size alone does not discard the source reps.
    private static func compactIcon(_ source: NSImage) -> NSImage {
        let targetSize = NSSize(width: 32, height: 32)
        let target = NSImage(size: targetSize)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: targetSize),
                    from: .zero,
                    operation: .copy,
                    fraction: 1.0)
        target.unlockFocus()
        target.isTemplate = source.isTemplate
        return target
    }

    private static func isAppleSignedApplication(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }

    private static let systemDaemonIdentifiers: Set<String> = [
        "mdnsresponder", "trustd", "apsd", "nsurlsessiond", "networkserviceproxy",
        "symptomsd", "configd", "rapportd", "sharingd", "locationd", "cloudd",
        "bird", "accountsd", "secd", "identityservicesd", "coreservicesuiagent"
    ]
}
