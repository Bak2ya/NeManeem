import Foundation

/// Keep this Objective-C protocol name and method signature identical to the
/// containing app's copy. XPC carries only JSON-encoded aggregate app/process byte counters.
@objc(NeManeemTrafficXPCProtocol)
protocol NeManeemTrafficXPCProtocol {
    func fetchTrafficSnapshot(withReply reply: @escaping (Data) -> Void)
    /// Lightweight Host liveness signal. Normal snapshot requests count as the
    /// same signal, so this is used only when blocking is active and traffic UI is idle.
    func reportHostLiveness(withReply reply: @escaping () -> Void)
}
