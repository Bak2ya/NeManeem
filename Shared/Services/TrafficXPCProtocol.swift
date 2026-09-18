import Foundation

/// Local-only IPC contract between the NeManeem app and its Network Extension.
/// The extension returns only aggregate app/process byte counters; network payload,
/// host names, URLs, endpoints, and browsing history are never transferred.
@objc(NeManeemTrafficXPCProtocol)
protocol NeManeemTrafficXPCProtocol {
    func fetchTrafficSnapshot(withReply reply: @escaping (Data) -> Void)
    /// Lightweight Host liveness signal. Normal snapshot requests count as the
    /// same signal, so this is used only when blocking is active and traffic UI is idle.
    func reportHostLiveness(withReply reply: @escaping () -> Void)
}
