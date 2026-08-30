import Foundation
import NetworkExtension
import OSLog

func main() -> Never {
    let logger = Logger(subsystem: "com.bak2ya.NeManeem.Filter", category: "Lifecycle")
    autoreleasepool {
        logger.notice("Network System Extension process entered main")
        // startSystemExtensionMode must happen before our named XPC listener.
        // Reversing the order can leave the listener invalidated on activation/update.
        NEProvider.startSystemExtensionMode()

        let networkExtensionInfo = Bundle.main.object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any]
        let machServiceName = networkExtensionInfo?["NEMachServiceName"] as? String ?? ""
        logger.notice("Network System Extension entered system-extension mode")
        if machServiceName.isEmpty {
            logger.error("NEMachServiceName is empty; host XPC cannot connect")
        } else {
            logger.notice("NEMachServiceName loaded successfully")
        }
        TrafficXPCServer.shared.start(machServiceName: machServiceName)
    }
    dispatchMain()
}

main()
