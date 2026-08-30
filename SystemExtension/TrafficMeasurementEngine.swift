import Foundation
import Security
import OSLog

// MARK: - Aggregate traffic counters

struct TrafficCounterSnapshot: Codable {
    struct Entry: Codable {
        /// Stable owning-app signing identifier. When macOS cannot provide an app
        /// audit token this falls back to the source process identifier.
        let identifier: String
        /// Actual source-process signing identifier when available. Optional keeps
        /// the JSON wire format backward-compatible with pre-0.4 extensions.
        let processIdentifier: String?
        let inboundBytes: UInt64
        let outboundBytes: UInt64
        let localInboundBytes: UInt64
        let localOutboundBytes: UInt64
        let unknownInboundBytes: UInt64
        let unknownOutboundBytes: UInt64
        let lastActivity: TimeInterval
    }

    /// Build 42 introduces owning-app + child-process hierarchy in the snapshot.
    /// Optional on the host side so Build 42 can still talk to an older active
    /// extension while macOS performs the replacement.
    let schemaVersion: Int
    let generatedAt: TimeInterval
    let engineStartedAt: TimeInterval
    let entries: [Entry]
}

/// Thread-safe, in-memory byte accounting shared by the filter provider and the
/// system extension's XPC endpoint. It intentionally stores no packet payload,
/// domain, URL, remote endpoint, or connection history.
final class TrafficMeasurementEngine {
    static let shared = TrafficMeasurementEngine()

    private struct CounterKey: Hashable {
        let appIdentifier: String
        let processIdentifier: String
    }

    private struct Counter {
        var inboundBytes: UInt64 = 0
        var outboundBytes: UInt64 = 0
        var localInboundBytes: UInt64 = 0
        var localOutboundBytes: UInt64 = 0
        var unknownInboundBytes: UInt64 = 0
        var unknownOutboundBytes: UInt64 = 0
        var lastActivity: TimeInterval = 0
    }

    private let lock = NSLock()
    private var counters: [CounterKey: Counter] = [:]
    private let startedAt = Date().timeIntervalSince1970

    private init() {}

    enum NetworkClass { case internet, local, unknown }

    /// Registers an app/process identity without claiming any traffic bytes.
    /// Report-only mode uses this at new-flow time so the host can populate the
    /// app control list even when periodic OS statistics contain zero byte counts.
    func observe(appIdentifier: String, processIdentifier: String) {
        let now = Date().timeIntervalSince1970
        let key = CounterKey(appIdentifier: appIdentifier, processIdentifier: processIdentifier)
        lock.lock()
        var counter = counters[key] ?? Counter()
        counter.lastActivity = now
        counters[key] = counter
        lock.unlock()
    }

    func record(appIdentifier: String,
                processIdentifier: String,
                inbound: UInt64 = 0,
                outbound: UInt64 = 0,
                networkClass: NetworkClass = .internet) {
        guard inbound > 0 || outbound > 0 else { return }
        let now = Date().timeIntervalSince1970
        let key = CounterKey(appIdentifier: appIdentifier, processIdentifier: processIdentifier)
        lock.lock()
        var counter = counters[key] ?? Counter()
        counter.inboundBytes &+= inbound
        counter.outboundBytes &+= outbound
        switch networkClass {
        case .internet: break
        case .local:
            counter.localInboundBytes &+= inbound
            counter.localOutboundBytes &+= outbound
        case .unknown:
            counter.unknownInboundBytes &+= inbound
            counter.unknownOutboundBytes &+= outbound
        }
        counter.lastActivity = now
        counters[key] = counter
        lock.unlock()
    }

    func snapshotData() -> Data {
        lock.lock()
        let values = counters.map { key, value in
            TrafficCounterSnapshot.Entry(identifier: key.appIdentifier,
                                         processIdentifier: key.processIdentifier,
                                         inboundBytes: value.inboundBytes,
                                         outboundBytes: value.outboundBytes,
                                         localInboundBytes: value.localInboundBytes,
                                         localOutboundBytes: value.localOutboundBytes,
                                         unknownInboundBytes: value.unknownInboundBytes,
                                         unknownOutboundBytes: value.unknownOutboundBytes,
                                         lastActivity: value.lastActivity)
        }
        lock.unlock()

        let snapshot = TrafficCounterSnapshot(schemaVersion: 7,
                                              generatedAt: Date().timeIntervalSince1970,
                                              engineStartedAt: startedAt,
                                              entries: values)
        return (try? JSONEncoder().encode(snapshot)) ?? Data()
    }
}

// MARK: - XPC server

/// XPC endpoint exposed by the macOS Network System Extension. The service name
/// comes from NEMachServiceName so nesessionmanager owns the Mach registration.
final class TrafficXPCServer: NSObject, NSXPCListenerDelegate, NeManeemTrafficXPCProtocol {
    static let shared = TrafficXPCServer()
    private let logger = Logger(subsystem: "com.bak2ya.NeManeem.Filter", category: "TrafficXPC")

    private var listener: NSXPCListener?
    private let expectedHostIdentifier = "com.bak2ya.NeManeem"
    private lazy var expectedHostRequirement: String? = Self.peerCodeSigningRequirement(bundleIdentifier: expectedHostIdentifier)
    private let diagnosticLock = NSLock()
    private var didLogFirstSnapshotRequest = false

    private override init() { super.init() }

    func start(machServiceName: String) {
        guard listener == nil, !machServiceName.isEmpty else {
            logger.error("XPC listener was not started because the Mach service name is empty or already active")
            return
        }
        logger.notice("Starting XPC listener service=\(machServiceName, privacy: .public)")
        let listener = NSXPCListener(machServiceName: machServiceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        logger.notice("XPC listener resumed and is waiting for host connections")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // macOS 13+ can validate the XPC peer directly from the connection's audit
        // credentials. This is both safer and more reliable for development-signed
        // apps launched by Xcode than reconstructing identity from a PID.
        guard let requirement = expectedHostRequirement else {
            logger.error("Rejecting XPC peer because host signing requirement could not be constructed")
            return false
        }
        logger.notice("XPC host connection candidate received; applying signing requirement")
        newConnection.setCodeSigningRequirement(requirement)
        newConnection.exportedInterface = NSXPCInterface(with: NeManeemTrafficXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.notice("Accepted host XPC connection invalidated")
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.notice("Accepted host XPC connection interrupted")
        }
        newConnection.resume()
        logger.notice("XPC host connection accepted and resumed")
        return true
    }

    func fetchTrafficSnapshot(withReply reply: @escaping (Data) -> Void) {
        diagnosticLock.lock()
        let shouldLog = !didLogFirstSnapshotRequest
        didLogFirstSnapshotRequest = true
        diagnosticLock.unlock()
        if shouldLog { logger.notice("XPC received its first traffic snapshot request") }
        reply(TrafficMeasurementEngine.shared.snapshotData())
    }

    private static func peerCodeSigningRequirement(bundleIdentifier: String) -> String? {
        guard let teamIdentifier = ownTeamIdentifier() else { return nil }
        return #"identifier "\#(bundleIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
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
}
