import Foundation

/// Local-only IPC contract between the NeManeem app and its Network Extension.
/// The extension returns only aggregate app/process byte counters; network payload,
/// host names, URLs, endpoints, and browsing history are never transferred.
@objc(NeManeemTrafficXPCProtocol)
protocol NeManeemTrafficXPCProtocol {
    func fetchTrafficSnapshot(withReply reply: @escaping (Data) -> Void)
}
