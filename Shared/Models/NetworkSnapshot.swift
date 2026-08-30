import Foundation

struct NetworkInterfaceCounterSnapshot: Equatable, Identifiable {
    var id: String { interfaceName }
    let interfaceName: String
    let networkIdentifier: String
    let networkDisplayName: String
    let identityReliable: Bool
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct NetworkSnapshot: Equatable {
    var downloadBytesPerSecond: UInt64 = 0
    var uploadBytesPerSecond: UInt64 = 0
    var totalReceivedBytes: UInt64 = 0
    var totalSentBytes: UInt64 = 0
    var interfaceDescription: String = "Network"
    var networkIdentifier: String = ""
    var networkDisplayName: String = ""
    var networkIdentityReliable: Bool = false
    var interfaceCounters: [NetworkInterfaceCounterSnapshot] = []
}
