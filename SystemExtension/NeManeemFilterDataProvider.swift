import Foundation
import NetworkExtension
import Security
import OSLog

@objc(NeManeemFilterDataProvider)
final class NeManeemFilterDataProvider: NEFilterDataProvider {
    private let logger = Logger(subsystem: "com.bak2ya.NeManeem.Filter", category: "FilterProvider")

    /// v0.5.21 selective live-metering + explicit Safari/WebKit compatibility policy.
    ///
    /// Safety rule first: local/unknown socket flows never enter payload callbacks.
    /// They keep the v0.5.10 report-only `.allow()` path so SMB/NAS traffic cannot be
    /// held behind NeManeem's data decisions. Positively-classified Internet socket flows may use sparse callbacks only
    /// to count byte offsets; the
    /// payload contents are never inspected, parsed, logged, or persisted.
    ///
    /// Known VPN transport daemons (currently Unicorn Pro's `unicornprod`) are also
    /// bypassed and excluded from user-facing accounting. Their tunnel bytes would
    /// otherwise duplicate the original source-app traffic and make every app appear
    /// as the VPN process.
    private enum MeasurementMode {
        case reportOnly
        case liveInternet
    }

    private final class FlowState {
        let appIdentifier: String
        let processIdentifier: String
        let networkClass: TrafficMeasurementEngine.NetworkClass
        let measurementMode: MeasurementMode
        var inboundReportedHighWater: UInt64 = 0
        var outboundReportedHighWater: UInt64 = 0
        var lastTouched = Date()

        init(appIdentifier: String,
             processIdentifier: String,
             networkClass: TrafficMeasurementEngine.NetworkClass,
             measurementMode: MeasurementMode) {
            self.appIdentifier = appIdentifier
            self.processIdentifier = processIdentifier
            self.networkClass = networkClass
            self.measurementMode = measurementMode
        }
    }

    private struct CodeIdentity {
        let signingIdentifier: String
        let owningAppIdentifier: String?
    }

    private let flowLock = NSLock()
    private var flowStates: [UUID: FlowState] = [:]
    private let codeIdentityLock = NSLock()
    private var codeIdentityCache: [Data: CodeIdentity] = [:]
    private let rulesLock = NSLock()
    private var lastRulesReloadAt = Date.distantPast
    private var blockedBundleIdentifiers = Set<String>()
    private var blockedProcessIdentifiers = Set<String>()
    private var blockingEnabled = false
    private var processBlockingEnabled = false
    private var dataLimitInternetBlocked = false
    private var dataLimitBlockLeaseExpiresAt: TimeInterval = 0
    private var safariNetworkServiceGroupingEnabled = false
    private var didLogFirstFlow = false
    private var didLogFirstReport = false
    private var didLogFirstMeasuredBytes = false
    private var didLogFirstLiveFlow = false
    private var didLogFirstRelayBypass = false
    private var didLogFirstAppProcessSplit = false
    private var liveCallbackCount: UInt64 = 0
    private var relayBypassFlowCount: UInt64 = 0
    private let unidentifiedIdentifier = "__nemaneem.unidentified__"

    // One byte is enough to wake the callback promptly. After each callback, pass a
    // large window immediately so high-throughput traffic is not forced through a
    // per-packet/per-4-KiB decision loop. The next callback's absolute offset reveals
    // how many bytes crossed the pass-ahead window without reading their contents.
    private let livePeekBytes = 1
    private let livePassAheadBytes = 1024 * 1024

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        reloadRules(force: true)
        logger.notice("HYBRID_SAFE provider starting: local/unknown report-only, selected Internet flows sparse-metered")
        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings) { [weak self] error in
            if let error {
                let nsError = error as NSError
                self?.logger.error("HYBRID_SAFE filter settings apply failed errorDomain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            } else {
                self?.logger.notice("HYBRID_SAFE provider active: SMB/local/unknown flows are never payload-callback metered")
            }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.notice("HYBRID_SAFE provider stopping reason=\(reason.rawValue, privacy: .public) liveCallbacks=\(self.liveCallbackCount, privacy: .public) relayBypassFlows=\(self.relayBypassFlowCount, privacy: .public)")
        flowLock.lock()
        flowStates.removeAll()
        flowLock.unlock()
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        // Do not reload the Network Extension vendor dictionary for every socket.
        // A 250 ms cache keeps new-connection handling lightweight while preserving
        // near-immediate policy updates.
        reloadRules(force: false)
        let identities = signingIdentifiers(for: flow)
        let appIdentifier = identities.app ?? identities.process ?? unidentifiedIdentifier
        let processIdentifier = identities.process ?? appIdentifier
        let flowNetworkClass = networkClass(for: flow)

        if appIdentifier != processIdentifier {
            var shouldLog = false
            flowLock.lock()
            if !didLogFirstAppProcessSplit {
                didLogFirstAppProcessSplit = true
                shouldLog = true
            }
            flowLock.unlock()
            if shouldLog {
                logger.notice("HYBRID_SAFE verified first source-app / source-process split for app-centric attribution")
            }
        }

        // A verified VPN transport daemon is infrastructure carrying other apps'
        // already-filtered traffic. Never put it into app accounting or app-level
        // blocking: blocking a hidden relay would black-hole every app behind the VPN.
        // Source-app flows are still evaluated by the normal blocking/data-limit rules.
        if isKnownTransportRelay(appIdentifier: appIdentifier, processIdentifier: processIdentifier) {
            var logFirstRelay = false
            flowLock.lock()
            relayBypassFlowCount &+= 1
            if !didLogFirstRelayBypass {
                didLogFirstRelayBypass = true
                logFirstRelay = true
            }
            flowLock.unlock()
            if logFirstRelay {
                logger.notice("HYBRID_SAFE detected known VPN transport relay; relay bypassed and excluded from app totals")
            }
            return .allow()
        }

        let rules = currentRules()
        if !appIdentifier.hasPrefix("com.bak2ya.NeManeem") {
            if rules.dataLimitInternetBlocked,
               rules.dataLimitBlockLeaseExpiresAt > Date().timeIntervalSince1970,
               flowNetworkClass != .local {
                logger.debug("HYBRID_SAFE dropped new flow by data-limit policy")
                return .drop()
            }
            let safariCompatibilityBlocked = rules.safariNetworkServiceGroupingEnabled &&
                rules.blockedBundleIdentifiers.contains("com.apple.Safari") &&
                isSafariNetworkServiceIdentifier(appIdentifier)
            let processBlocked = rules.processBlockingEnabled &&
                rules.blockedProcessIdentifiers.contains(processIdentifier)
            if rules.blockingEnabled,
               rules.blockedBundleIdentifiers.contains(appIdentifier) || safariCompatibilityBlocked || processBlocked {
                logger.debug("HYBRID_SAFE dropped new flow by app policy")
                return .drop()
            }
        }

        let measurementMode: MeasurementMode = shouldLiveMeter(flow: flow, networkClass: flowNetworkClass)
            ? .liveInternet
            : .reportOnly

        TrafficMeasurementEngine.shared.observe(appIdentifier: appIdentifier,
                                                processIdentifier: processIdentifier)

        let state = FlowState(appIdentifier: appIdentifier,
                              processIdentifier: processIdentifier,
                              networkClass: flowNetworkClass,
                              measurementMode: measurementMode)
        var logFirstFlow = false
        var logFirstLive = false
        flowLock.lock()
        flowStates[flow.identifier] = state
        if !didLogFirstFlow {
            didLogFirstFlow = true
            logFirstFlow = true
        }
        if measurementMode == .liveInternet, !didLogFirstLiveFlow {
            didLogFirstLiveFlow = true
            logFirstLive = true
        }
        pruneFlowStatesIfNeeded(now: Date())
        flowLock.unlock()

        if logFirstFlow { logger.notice("HYBRID_SAFE received first network flow") }
        if logFirstLive { logger.notice("HYBRID_SAFE first source-app Internet flow entered sparse live metering") }

        switch measurementMode {
        case .liveInternet:
            let verdict = NEFilterNewFlowVerdict.filterDataVerdict(withFilterInbound: true,
                                                                    peekInboundBytes: livePeekBytes,
                                                                    filterOutbound: true,
                                                                    peekOutboundBytes: livePeekBytes)
            verdict.shouldReport = true
            return verdict

        case .reportOnly:
            let verdict = NEFilterNewFlowVerdict.allow()
            verdict.shouldReport = true
            return verdict
        }
    }

    override func handleInboundData(from flow: NEFilterFlow,
                                    readBytesStartOffset offset: Int,
                                    readBytes: Data) -> NEFilterDataVerdict {
        recordLiveData(flow: flow, inbound: true, offset: offset, readCount: readBytes.count)
        return sparseContinueVerdict()
    }

    override func handleOutboundData(from flow: NEFilterFlow,
                                     readBytesStartOffset offset: Int,
                                     readBytes: Data) -> NEFilterDataVerdict {
        recordLiveData(flow: flow, inbound: false, offset: offset, readCount: readBytes.count)
        return sparseContinueVerdict()
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        return completionVerdict()
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        return completionVerdict()
    }

    override func handle(_ report: NEFilterReport) {
        guard let flow = report.flow else {
            logger.debug("HYBRID_SAFE report without flow event=\(report.event.rawValue, privacy: .public)")
            return
        }

        var logFirst = false
        flowLock.lock()
        if !didLogFirstReport {
            didLogFirstReport = true
            logFirst = true
        }
        flowLock.unlock()
        if logFirst { logger.notice("HYBRID_SAFE received first OS filter report") }

        switch report.event {
        case .flowClosed:
            // Apple's public contract guarantees these counters on flowClosed. They
            // also close the final gap after the last sparse live callback.
            let inbound = UInt64(max(0, report.bytesInboundCount))
            let outbound = UInt64(max(0, report.bytesOutboundCount))
            recordReportCounters(flow: flow,
                                 inboundTotal: inbound,
                                 outboundTotal: outbound,
                                 removeStateAfterward: true)

        case .statistics:
            // Current public docs say byte counters are zero for this event. Do not
            // depend on them; keep the event only as a diagnostics signal.
            logger.debug("HYBRID_SAFE statistics report received")

        default:
            logger.debug("HYBRID_SAFE OS report event=\(report.event.rawValue, privacy: .public)")
        }
    }

    private func recordLiveData(flow: NEFilterFlow,
                                inbound: Bool,
                                offset: Int,
                                readCount: Int) {
        let safeOffset = UInt64(max(0, offset))
        let observedEnd = safeOffset &+ UInt64(max(0, readCount))
        var appIdentifier: String?
        var processIdentifier: String?
        var networkClass: TrafficMeasurementEngine.NetworkClass = .unknown
        var delta: UInt64 = 0

        flowLock.lock()
        if let state = flowStates[flow.identifier], state.measurementMode == .liveInternet {
            if inbound {
                if observedEnd > state.inboundReportedHighWater {
                    delta = observedEnd - state.inboundReportedHighWater
                    state.inboundReportedHighWater = observedEnd
                }
            } else if observedEnd > state.outboundReportedHighWater {
                delta = observedEnd - state.outboundReportedHighWater
                state.outboundReportedHighWater = observedEnd
            }
            state.lastTouched = Date()
            appIdentifier = state.appIdentifier
            processIdentifier = state.processIdentifier
            networkClass = state.networkClass
            liveCallbackCount &+= 1
        }
        flowLock.unlock()

        guard delta > 0 else { return }
        recordMeasuredBytes(appIdentifier: appIdentifier,
                            processIdentifier: processIdentifier,
                            networkClass: networkClass,
                            inboundBytes: inbound ? delta : 0,
                            outboundBytes: inbound ? 0 : delta)
    }

    private func sparseContinueVerdict() -> NEFilterDataVerdict {
        let verdict = NEFilterDataVerdict(passBytes: livePassAheadBytes, peekBytes: livePeekBytes)
        verdict.shouldReport = true
        return verdict
    }

    private func completionVerdict() -> NEFilterDataVerdict {
        let verdict = NEFilterDataVerdict.allow()
        verdict.shouldReport = true
        return verdict
    }

    private func recordReportCounters(flow: NEFilterFlow,
                                      inboundTotal: UInt64,
                                      outboundTotal: UInt64,
                                      removeStateAfterward: Bool) {
        var appIdentifier: String?
        var processIdentifier: String?
        var flowNetworkClass: TrafficMeasurementEngine.NetworkClass = .unknown
        var inboundDelta: UInt64 = 0
        var outboundDelta: UInt64 = 0
        var shouldRecord = false

        flowLock.lock()
        if let state = flowStates[flow.identifier] {
            shouldRecord = true
            if shouldRecord {
                if inboundTotal > state.inboundReportedHighWater {
                    inboundDelta = inboundTotal - state.inboundReportedHighWater
                    state.inboundReportedHighWater = inboundTotal
                }
                if outboundTotal > state.outboundReportedHighWater {
                    outboundDelta = outboundTotal - state.outboundReportedHighWater
                    state.outboundReportedHighWater = outboundTotal
                }
                appIdentifier = state.appIdentifier
                processIdentifier = state.processIdentifier
                flowNetworkClass = state.networkClass
            }
            state.lastTouched = Date()
            if removeStateAfterward {
                flowStates.removeValue(forKey: flow.identifier)
            }
        }
        flowLock.unlock()

        guard shouldRecord else { return }
        recordMeasuredBytes(appIdentifier: appIdentifier,
                            processIdentifier: processIdentifier,
                            networkClass: flowNetworkClass,
                            inboundBytes: inboundDelta,
                            outboundBytes: outboundDelta)
    }

    private func recordMeasuredBytes(appIdentifier: String?,
                                     processIdentifier: String?,
                                     networkClass: TrafficMeasurementEngine.NetworkClass,
                                     inboundBytes: UInt64,
                                     outboundBytes: UInt64) {
        guard let appIdentifier, let processIdentifier,
              inboundBytes > 0 || outboundBytes > 0 else { return }

        var logFirst = false
        flowLock.lock()
        if !didLogFirstMeasuredBytes {
            didLogFirstMeasuredBytes = true
            logFirst = true
        }
        flowLock.unlock()
        if logFirst { logger.notice("HYBRID_SAFE recorded first source-app traffic bytes") }

        if inboundBytes > 0 {
            TrafficMeasurementEngine.shared.record(appIdentifier: appIdentifier,
                                                   processIdentifier: processIdentifier,
                                                   inbound: inboundBytes,
                                                   networkClass: networkClass)
        }
        if outboundBytes > 0 {
            TrafficMeasurementEngine.shared.record(appIdentifier: appIdentifier,
                                                   processIdentifier: processIdentifier,
                                                   outbound: outboundBytes,
                                                   networkClass: networkClass)
        }
    }

    private func pruneFlowStatesIfNeeded(now: Date) {
        guard flowStates.count > 4096 else { return }
        let cutoff = now.addingTimeInterval(-30 * 60)
        flowStates = flowStates.filter { $0.value.lastTouched >= cutoff }
        if flowStates.count > 4096 {
            let oldest = flowStates.sorted { $0.value.lastTouched < $1.value.lastTouched }
            for (id, _) in oldest.prefix(flowStates.count - 3072) {
                flowStates.removeValue(forKey: id)
            }
        }
    }

    /// macOS content-filter data providers receive socket flows for this path.
    /// Only positively classified Internet socket flows enter sparse live metering;
    /// local/unknown/non-socket flows stay on the report-only path. This preserves
    /// the NAS/SMB safety boundary and avoids using NEFilterBrowserFlow, which is
    /// unavailable to macOS targets.
    private func shouldLiveMeter(flow: NEFilterFlow,
                                 networkClass: TrafficMeasurementEngine.NetworkClass) -> Bool {
        guard flow is NEFilterSocketFlow else { return false }
        return networkClass == .internet
    }

    /// Compatibility layer for transport processes that multiplex other apps' bytes.
    /// Add only identifiers verified in real user traces; never guess broad VPN names.
    private func isKnownTransportRelay(appIdentifier: String, processIdentifier: String) -> Bool {
        let process = processIdentifier.lowercased()
        let app = appIdentifier.lowercased()
        return process == "unicornprod" || process.hasSuffix(".unicornprod") ||
            app == "unicornprod" || app.hasSuffix(".unicornprod")
    }

    // macOS exposes separate audit tokens for the source application and the process
    // that actually created the socket. Resolve both, then present the source app as
    // the ordinary user-facing owner while retaining the raw process for expert
    // drill-down. Do not use NEFilterFlow.sourceAppIdentifier here: that property is
    // unavailable to macOS targets.
    //
    // If the source-app token resolves to a helper nested inside a user-facing .app,
    // promote it to the outer app bundle. This handles nested helpers such as Chrome
    // Helper without hardcoding a process name or guessing traffic ownership.
    private func signingIdentifiers(for flow: NEFilterFlow) -> (app: String?, process: String?) {
        let appToken = flow.sourceAppAuditToken
        let processToken = flow.sourceProcessAuditToken

        let processIdentity = processToken.flatMap { codeIdentity(auditToken: $0) }
        let appIdentity: CodeIdentity?
        if let appToken, let processToken, appToken == processToken {
            appIdentity = processIdentity
        } else {
            appIdentity = appToken.flatMap { codeIdentity(auditToken: $0) }
        }

        let process = processIdentity?.signingIdentifier ?? appIdentity?.signingIdentifier
        let owner = appIdentity?.owningAppIdentifier
            ?? appIdentity?.signingIdentifier
            ?? processIdentity?.owningAppIdentifier
            ?? process

        return (owner, process)
    }

    private func codeIdentity(auditToken: Data) -> CodeIdentity? {
        codeIdentityLock.lock()
        if let cached = codeIdentityCache[auditToken] {
            codeIdentityLock.unlock()
            return cached
        }
        codeIdentityLock.unlock()

        let attributes = [kSecGuestAttributeAudit: auditToken as CFData] as CFDictionary
        var dynamicCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &dynamicCode) == errSecSuccess,
              let dynamicCode else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &signingInfo) == errSecSuccess,
              let info = signingInfo as? [CFString: Any],
              let identifier = info[kSecCodeInfoIdentifier] as? String else { return nil }

        let executableURL = info[kSecCodeInfoMainExecutable] as? URL
        let owner = executableURL.flatMap { owningApplicationIdentifier(containing: $0) }
        let value = CodeIdentity(signingIdentifier: identifier, owningAppIdentifier: owner)

        codeIdentityLock.lock()
        if codeIdentityCache.count >= 512 {
            // Audit tokens are process-scoped. Bound the cache so long-running Macs
            // that create many short-lived helpers cannot grow it indefinitely.
            codeIdentityCache.removeAll(keepingCapacity: true)
        }
        codeIdentityCache[auditToken] = value
        codeIdentityLock.unlock()
        return value
    }

    /// Returns a verified owning application only when the signed executable lives
    /// inside an .app bundle. For nested helper apps (for example Chrome Helper.app
    /// inside Google Chrome.app), choose the outermost .app so ordinary UI follows
    /// the application the user actually launched. Paths are used transiently and
    /// are never stored or logged.
    private func owningApplicationIdentifier(containing executableURL: URL) -> String? {
        let components = executableURL.standardizedFileURL.pathComponents
        guard !components.isEmpty else { return nil }

        var current = URL(fileURLWithPath: "/", isDirectory: true)
        var outermostAppURL: URL?
        for component in components.dropFirst() {
            current.appendPathComponent(component)
            if outermostAppURL == nil, component.lowercased().hasSuffix(".app") {
                outermostAppURL = current
            }
        }
        guard let outermostAppURL,
              let bundle = Bundle(url: outermostAppURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else { return nil }
        return bundleIdentifier
    }

    /// Classify once per socket flow from the remote endpoint. The endpoint itself
    /// is never persisted or logged; only local/internet/unknown is retained.
    private func networkClass(for flow: NEFilterFlow) -> TrafficMeasurementEngine.NetworkClass {
        guard let socketFlow = flow as? NEFilterSocketFlow,
              let endpoint = socketFlow.remoteEndpoint as? NWHostEndpoint else { return .unknown }
        let host = endpoint.hostname.lowercased()
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" || host.hasPrefix("127.") || host.hasPrefix("169.254.") || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return .local }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            if parts[0] == 10 { return .local }
            if parts[0] == 192 && parts[1] == 168 { return .local }
            if parts[0] == 172 && (16...31).contains(parts[1]) { return .local }
            return .internet
        }
        return .unknown
    }

    private func isSafariNetworkServiceIdentifier(_ identifier: String) -> Bool {
        identifier.lowercased().contains("webkit.networking")
    }

    private func currentRules() -> (blockedBundleIdentifiers: Set<String>, blockedProcessIdentifiers: Set<String>, blockingEnabled: Bool, processBlockingEnabled: Bool, dataLimitInternetBlocked: Bool, dataLimitBlockLeaseExpiresAt: TimeInterval, safariNetworkServiceGroupingEnabled: Bool) {
        rulesLock.lock()
        defer { rulesLock.unlock() }
        return (blockedBundleIdentifiers, blockedProcessIdentifiers, blockingEnabled, processBlockingEnabled, dataLimitInternetBlocked, dataLimitBlockLeaseExpiresAt, safariNetworkServiceGroupingEnabled)
    }

    private func reloadRules(force: Bool = false) {
        let now = Date()
        rulesLock.lock()
        if !force, now.timeIntervalSince(lastRulesReloadAt) < 0.25 {
            rulesLock.unlock()
            return
        }
        let configuration = filterConfiguration.vendorConfiguration ?? [:]
        let values = configuration["blockedBundleIdentifiers"] as? [String] ?? []
        blockedBundleIdentifiers = Set(values)
        let processValues = configuration["blockedProcessIdentifiers"] as? [String] ?? []
        blockedProcessIdentifiers = Set(processValues.filter { isBlockableProcessIdentifier($0) })
        blockingEnabled = configuration["blockingEnabled"] as? Bool ?? false
        processBlockingEnabled = configuration["processBlockingEnabled"] as? Bool ?? false
        dataLimitInternetBlocked = configuration["dataLimitInternetBlocked"] as? Bool ?? false
        dataLimitBlockLeaseExpiresAt = configuration["dataLimitBlockLeaseExpiresAt"] as? Double ?? 0
        safariNetworkServiceGroupingEnabled = configuration["safariNetworkServiceGroupingEnabled"] as? Bool ?? false
        lastRulesReloadAt = now
        rulesLock.unlock()
    }

    private func isBlockableProcessIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty &&
        !identifier.hasPrefix("__nemaneem.") &&
        !identifier.hasPrefix("com.bak2ya.NeManeem") &&
        identifier.lowercased() != "unicornprod" &&
        !identifier.lowercased().hasSuffix(".unicornprod")
    }
}
