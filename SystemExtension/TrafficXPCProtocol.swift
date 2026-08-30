import Foundation

/// Keep this Objective-C protocol name and method signature identical to the
/// containing app's copy. XPC carries only JSON-encoded aggregate app/process byte counters.
@objc(NeManeemTrafficXPCProtocol)
protocol NeManeemTrafficXPCProtocol {
    func fetchTrafficSnapshot(withReply reply: @escaping (Data) -> Void)
}
