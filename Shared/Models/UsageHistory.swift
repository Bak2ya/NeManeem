import Foundation

struct AppBytePair: Codable, Equatable {
    var download: UInt64 = 0
    var upload: UInt64 = 0
    var localDownload: UInt64 = 0
    var localUpload: UInt64 = 0
    var unknownDownload: UInt64 = 0
    var unknownUpload: UInt64 = 0

    enum CodingKeys: String, CodingKey {
        case download, upload, localDownload, localUpload, unknownDownload, unknownUpload
    }

    init(download: UInt64 = 0,
         upload: UInt64 = 0,
         localDownload: UInt64 = 0,
         localUpload: UInt64 = 0,
         unknownDownload: UInt64 = 0,
         unknownUpload: UInt64 = 0) {
        self.download = download
        self.upload = upload
        self.localDownload = localDownload
        self.localUpload = localUpload
        self.unknownDownload = unknownDownload
        self.unknownUpload = unknownUpload
    }

    func totalBytes(for scope: TrafficValueScope) -> UInt64 {
        switch scope {
        case .all:
            return download &+ upload
        case .local:
            return localDownload &+ localUpload
        case .unknown:
            return unknownDownload &+ unknownUpload
        case .internet:
            let downExcluded = localDownload &+ unknownDownload
            let upExcluded = localUpload &+ unknownUpload
            let internetDown = download >= downExcluded ? download - downExcluded : 0
            let internetUp = upload >= upExcluded ? upload - upExcluded : 0
            return internetDown &+ internetUp
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        download = try c.decodeIfPresent(UInt64.self, forKey: .download) ?? 0
        upload = try c.decodeIfPresent(UInt64.self, forKey: .upload) ?? 0
        localDownload = try c.decodeIfPresent(UInt64.self, forKey: .localDownload) ?? 0
        localUpload = try c.decodeIfPresent(UInt64.self, forKey: .localUpload) ?? 0
        unknownDownload = try c.decodeIfPresent(UInt64.self, forKey: .unknownDownload) ?? 0
        unknownUpload = try c.decodeIfPresent(UInt64.self, forKey: .unknownUpload) ?? 0
    }
}

struct ProcessUsageHistoryValue: Codable, Equatable {
    var displayName: String
    var bundleIdentifier: String?
    var bytes: AppBytePair

    init(displayName: String, bundleIdentifier: String?, bytes: AppBytePair) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.bytes = bytes
    }
}

struct UsageBucket: Codable, Identifiable, Equatable {
    // Build 37 can store more than one physical-network slice in the same minute.
    // Keep the identifier derived so older JSON files remain source-compatible.
    var id: String { "\(start.timeIntervalSince1970)|\(networkIdentifier ?? "legacy")" }
    let start: Date
    var download: UInt64
    var upload: UInt64
    var apps: [String: AppBytePair]
    // Optional for backward compatibility. When enabled, 0.4 records the
    // lower-level source processes in addition to the normal app aggregate.
    // Older history files simply decode this as nil.
    var processes: [String: ProcessUsageHistoryValue]?
    var networkIdentifier: String?
    var networkDisplayName: String?
    var networkIdentityReliable: Bool?
    // v0.5.0 can retain only anonymous Internet totals for a minute. This lets
    // Data Limit stay exact in Austerity mode without persisting app identities.
    var classifiedInternetDownload: UInt64?
    var classifiedInternetUpload: UInt64?

    init(start: Date,
         download: UInt64,
         upload: UInt64,
         apps: [String: AppBytePair],
         processes: [String: ProcessUsageHistoryValue]? = nil,
         networkIdentifier: String? = nil,
         networkDisplayName: String? = nil,
         networkIdentityReliable: Bool? = nil,
         classifiedInternetDownload: UInt64? = nil,
         classifiedInternetUpload: UInt64? = nil) {
        self.start = start
        self.download = download
        self.upload = upload
        self.apps = apps
        self.processes = processes
        self.networkIdentifier = networkIdentifier
        self.networkDisplayName = networkDisplayName
        self.networkIdentityReliable = networkIdentityReliable
        self.classifiedInternetDownload = classifiedInternetDownload
        self.classifiedInternetUpload = classifiedInternetUpload
    }
}

struct AppUsageRecommendationStat: Identifiable, Hashable {
    let id: String
    let totalBytes: UInt64
    let activeDays: Int
}

struct RecordedNetworkIdentity: Identifiable, Hashable {
    let id: String
    let displayName: String
    let reliable: Bool
}

struct UsagePoint: Identifiable {
    let id = UUID()
    let start: Date
    let download: UInt64
    let upload: UInt64
}

struct DataUsageRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let download: UInt64
    let upload: UInt64
    let limitBytes: UInt64
    /// Optional label used for clearly marked preview/test records. Real cycle records
    /// normally leave this nil, keeping older archives source-compatible.
    let label: String?
    // Optional so Build 36-and-earlier archives keep decoding unchanged.
    let networkIdentifier: String?
    let networkDisplayName: String?

    init(id: UUID = UUID(),
         start: Date,
         end: Date,
         download: UInt64,
         upload: UInt64,
         limitBytes: UInt64,
         label: String? = nil,
         networkIdentifier: String? = nil,
         networkDisplayName: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.download = download
        self.upload = upload
        self.limitBytes = limitBytes
        self.label = label
        self.networkIdentifier = networkIdentifier
        self.networkDisplayName = networkDisplayName
    }

    var total: UInt64 { download &+ upload }
}

struct UsageSessionSegment: Codable, Equatable {
    var start: Date
    var end: Date?
}

struct UsageSessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String?
    let start: Date
    let end: Date
    let download: UInt64
    let upload: UInt64

    init(id: UUID = UUID(), name: String? = nil, start: Date, end: Date, download: UInt64, upload: UInt64) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.download = download
        self.upload = upload
    }

    var total: UInt64 { download &+ upload }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct ActiveUsageSessionState: Codable, Equatable {
    var startedAt: Date
    var paused: Bool
    var segments: [UsageSessionSegment]
}
