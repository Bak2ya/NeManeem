import AppKit
import Foundation

enum TrafficValueScope {
    case all
    case internet
    case local
    case unknown
}

struct AppNetworkUsage: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// Stable owning-app bundle/signing identifier when macOS can provide it.
    let bundleIdentifier: String?
    /// Actual source-process signing identifier for optional expert drill-down.
    let processIdentifier: String?
    /// User-facing owner app name. Child process rows keep their own `displayName`.
    let appDisplayName: String?
    let icon: NSImage
    let isSystemProcess: Bool
    let isAppleApp: Bool
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
    let localDownloadBytesPerSecond: UInt64
    let localUploadBytesPerSecond: UInt64
    let unknownDownloadBytesPerSecond: UInt64
    let unknownUploadBytesPerSecond: UInt64
    /// Monotonic byte totals reported by the Network Extension for this source app.
    /// These let history recording remain exact even when UI refresh intervals vary.
    let cumulativeDownloadBytes: UInt64
    let cumulativeUploadBytes: UInt64
    let cumulativeLocalDownloadBytes: UInt64
    let cumulativeLocalUploadBytes: UInt64
    let cumulativeUnknownDownloadBytes: UInt64
    let cumulativeUnknownUploadBytes: UInt64
    let lastActiveAt: Date

    /// Explicit initializer keeps the original call sites source-compatible while
    /// allowing the Local/Unknown counters added in Build 27 to be supplied when
    /// available. Defaults belong on initializer parameters rather than `let`
    /// stored properties; a default value on a `let` property removes that field
    /// from Swift's synthesized memberwise initializer.
    init(id: String,
         displayName: String,
         bundleIdentifier: String?,
         processIdentifier: String? = nil,
         appDisplayName: String? = nil,
         icon: NSImage,
         isSystemProcess: Bool,
         isAppleApp: Bool,
         downloadBytesPerSecond: UInt64,
         uploadBytesPerSecond: UInt64,
         localDownloadBytesPerSecond: UInt64 = 0,
         localUploadBytesPerSecond: UInt64 = 0,
         unknownDownloadBytesPerSecond: UInt64 = 0,
         unknownUploadBytesPerSecond: UInt64 = 0,
         cumulativeDownloadBytes: UInt64,
         cumulativeUploadBytes: UInt64,
         cumulativeLocalDownloadBytes: UInt64 = 0,
         cumulativeLocalUploadBytes: UInt64 = 0,
         cumulativeUnknownDownloadBytes: UInt64 = 0,
         cumulativeUnknownUploadBytes: UInt64 = 0,
         lastActiveAt: Date) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.appDisplayName = appDisplayName
        self.icon = icon
        self.isSystemProcess = isSystemProcess
        self.isAppleApp = isAppleApp
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.localDownloadBytesPerSecond = localDownloadBytesPerSecond
        self.localUploadBytesPerSecond = localUploadBytesPerSecond
        self.unknownDownloadBytesPerSecond = unknownDownloadBytesPerSecond
        self.unknownUploadBytesPerSecond = unknownUploadBytesPerSecond
        self.cumulativeDownloadBytes = cumulativeDownloadBytes
        self.cumulativeUploadBytes = cumulativeUploadBytes
        self.cumulativeLocalDownloadBytes = cumulativeLocalDownloadBytes
        self.cumulativeLocalUploadBytes = cumulativeLocalUploadBytes
        self.cumulativeUnknownDownloadBytes = cumulativeUnknownDownloadBytes
        self.cumulativeUnknownUploadBytes = cumulativeUnknownUploadBytes
        self.lastActiveAt = lastActiveAt
    }

    var totalBytesPerSecond: UInt64 { downloadBytesPerSecond + uploadBytesPerSecond }
    /// Safari is intentionally kept outside the generic Apple-app group by default.
    /// It is a high-traffic, user-facing browser, so hiding it inside a bundle would
    /// make the primary network view less useful even when Apple grouping is enabled.
    var isSafari: Bool {
        bundleIdentifier == "com.apple.Safari" || id == "com.apple.Safari"
    }
    var internetDownloadBytesPerSecond: UInt64 { downloadBytesPerSecond >= localDownloadBytesPerSecond &+ unknownDownloadBytesPerSecond ? downloadBytesPerSecond - localDownloadBytesPerSecond - unknownDownloadBytesPerSecond : 0 }
    var internetUploadBytesPerSecond: UInt64 { uploadBytesPerSecond >= localUploadBytesPerSecond &+ unknownUploadBytesPerSecond ? uploadBytesPerSecond - localUploadBytesPerSecond - unknownUploadBytesPerSecond : 0 }
    var isActive: Bool { totalBytesPerSecond > 0 }

    func downloadBytesPerSecond(for scope: TrafficValueScope) -> UInt64 {
        switch scope {
        case .all: return downloadBytesPerSecond
        case .internet: return internetDownloadBytesPerSecond
        case .local: return localDownloadBytesPerSecond
        case .unknown: return unknownDownloadBytesPerSecond
        }
    }

    func uploadBytesPerSecond(for scope: TrafficValueScope) -> UInt64 {
        switch scope {
        case .all: return uploadBytesPerSecond
        case .internet: return internetUploadBytesPerSecond
        case .local: return localUploadBytesPerSecond
        case .unknown: return unknownUploadBytesPerSecond
        }
    }

    static func == (lhs: AppNetworkUsage, rhs: AppNetworkUsage) -> Bool {
        lhs.id == rhs.id &&
        lhs.displayName == rhs.displayName &&
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.processIdentifier == rhs.processIdentifier &&
        lhs.appDisplayName == rhs.appDisplayName &&
        lhs.isSystemProcess == rhs.isSystemProcess &&
        lhs.isAppleApp == rhs.isAppleApp &&
        lhs.downloadBytesPerSecond == rhs.downloadBytesPerSecond &&
        lhs.uploadBytesPerSecond == rhs.uploadBytesPerSecond &&
        lhs.localDownloadBytesPerSecond == rhs.localDownloadBytesPerSecond &&
        lhs.localUploadBytesPerSecond == rhs.localUploadBytesPerSecond &&
        lhs.unknownDownloadBytesPerSecond == rhs.unknownDownloadBytesPerSecond &&
        lhs.unknownUploadBytesPerSecond == rhs.unknownUploadBytesPerSecond &&
        lhs.cumulativeDownloadBytes == rhs.cumulativeDownloadBytes &&
        lhs.cumulativeUploadBytes == rhs.cumulativeUploadBytes &&
        lhs.cumulativeLocalDownloadBytes == rhs.cumulativeLocalDownloadBytes &&
        lhs.cumulativeLocalUploadBytes == rhs.cumulativeLocalUploadBytes &&
        lhs.cumulativeUnknownDownloadBytes == rhs.cumulativeUnknownDownloadBytes &&
        lhs.cumulativeUnknownUploadBytes == rhs.cumulativeUnknownUploadBytes &&
        lhs.lastActiveAt == rhs.lastActiveAt
    }
}


/// User-facing app selection is stored by the most stable app identity available.
/// The Network Extension may still report a lower-level source process in some
/// flows; keeping the raw id as a fallback preserves those legacy selections.
func appSelectionKey(_ usage: AppNetworkUsage) -> String {
    if let bundleIdentifier = usage.bundleIdentifier, !bundleIdentifier.isEmpty {
        return bundleIdentifier
    }
    return usage.id
}

func isSafariNetworkServiceUsage(_ usage: AppNetworkUsage) -> Bool {
    [usage.id, usage.bundleIdentifier, usage.processIdentifier].contains { value in
        value?.lowercased().contains("webkit.networking") == true
    }
}

func isAppUsageSelected(_ usage: AppNetworkUsage, selectedIDs: Set<String>) -> Bool {
    selectedIDs.contains(usage.id) || selectedIDs.contains(appSelectionKey(usage))
}

/// Per-view baseline used to derive a live rate from the Network Extension's
/// monotonic cumulative counters. This lets Popover and Monitor use different
/// real sampling cadences even when both are open at the same time.
struct AppUsageCounterBaseline: Equatable {
    let download: UInt64
    let upload: UInt64
    let localDownload: UInt64
    let localUpload: UInt64
    let unknownDownload: UInt64
    let unknownUpload: UInt64
}

func appUsageCounterBaseline(_ usages: [AppNetworkUsage]) -> [String: AppUsageCounterBaseline] {
    Dictionary(uniqueKeysWithValues: usages.map {
        ($0.id, AppUsageCounterBaseline(download: $0.cumulativeDownloadBytes,
                                        upload: $0.cumulativeUploadBytes,
                                        localDownload: $0.cumulativeLocalDownloadBytes,
                                        localUpload: $0.cumulativeLocalUploadBytes,
                                        unknownDownload: $0.cumulativeUnknownDownloadBytes,
                                        unknownUpload: $0.cumulativeUnknownUploadBytes))
    })
}

/// Sparse-checkpoint Network Extension accounting can update more slowly than a
/// view's requested refresh interval. A view must not advance its rate baseline
/// when cumulative counters have not changed, or a 0.25 s UI interval can alternate
/// between zero and an artificial spike at the next checkpoint.
func appUsageCountersChanged(_ usages: [AppNetworkUsage],
                             from baseline: [String: AppUsageCounterBaseline]) -> Bool {
    let current = appUsageCounterBaseline(usages)
    return current != baseline
}

func resampledAppNetworkUsages(_ usages: [AppNetworkUsage],
                               from baseline: [String: AppUsageCounterBaseline],
                               elapsed: TimeInterval) -> [AppNetworkUsage] {
    let seconds = max(elapsed, 0.001)
    return usages.map { usage in
        let previous = baseline[usage.id]
        let downloadDelta: UInt64
        let uploadDelta: UInt64
        let localDownloadDelta: UInt64
        let localUploadDelta: UInt64
        let unknownDownloadDelta: UInt64
        let unknownUploadDelta: UInt64
        if let previous,
           usage.cumulativeDownloadBytes >= previous.download,
           usage.cumulativeUploadBytes >= previous.upload {
            downloadDelta = usage.cumulativeDownloadBytes - previous.download
            uploadDelta = usage.cumulativeUploadBytes - previous.upload
            localDownloadDelta = usage.cumulativeLocalDownloadBytes >= previous.localDownload ? usage.cumulativeLocalDownloadBytes - previous.localDownload : 0
            localUploadDelta = usage.cumulativeLocalUploadBytes >= previous.localUpload ? usage.cumulativeLocalUploadBytes - previous.localUpload : 0
            unknownDownloadDelta = usage.cumulativeUnknownDownloadBytes >= previous.unknownDownload ? usage.cumulativeUnknownDownloadBytes - previous.unknownDownload : 0
            unknownUploadDelta = usage.cumulativeUnknownUploadBytes >= previous.unknownUpload ? usage.cumulativeUnknownUploadBytes - previous.unknownUpload : 0
        } else {
            // New process or extension restart: establish a baseline instead of
            // inventing a rate from an unknown starting point.
            downloadDelta = 0
            uploadDelta = 0
            localDownloadDelta = 0
            localUploadDelta = 0
            unknownDownloadDelta = 0
            unknownUploadDelta = 0
        }

        return AppNetworkUsage(
            id: usage.id,
            displayName: usage.displayName,
            bundleIdentifier: usage.bundleIdentifier,
            processIdentifier: usage.processIdentifier,
            appDisplayName: usage.appDisplayName,
            icon: usage.icon,
            isSystemProcess: usage.isSystemProcess,
            isAppleApp: usage.isAppleApp,
            downloadBytesPerSecond: UInt64(Double(downloadDelta) / seconds),
            uploadBytesPerSecond: UInt64(Double(uploadDelta) / seconds),
            localDownloadBytesPerSecond: UInt64(Double(localDownloadDelta) / seconds),
            localUploadBytesPerSecond: UInt64(Double(localUploadDelta) / seconds),
            unknownDownloadBytesPerSecond: UInt64(Double(unknownDownloadDelta) / seconds),
            unknownUploadBytesPerSecond: UInt64(Double(unknownUploadDelta) / seconds),
            cumulativeDownloadBytes: usage.cumulativeDownloadBytes,
            cumulativeUploadBytes: usage.cumulativeUploadBytes,
            cumulativeLocalDownloadBytes: usage.cumulativeLocalDownloadBytes,
            cumulativeLocalUploadBytes: usage.cumulativeLocalUploadBytes,
            cumulativeUnknownDownloadBytes: usage.cumulativeUnknownDownloadBytes,
            cumulativeUnknownUploadBytes: usage.cumulativeUnknownUploadBytes,
            lastActiveAt: usage.lastActiveAt
        )
    }
}

/// User-facing grouping model for 0.4. NeManeem still measures the original
/// source processes, but ordinary status UI presents one row per app. The raw
/// members are retained so an expert can expand the row and inspect them.
struct AppUsageGroup: Identifiable {
    let id: String
    let usage: AppNetworkUsage
    let members: [AppNetworkUsage]

    var isExpandable: Bool {
        members.count > 1 || members.contains {
            guard let processIdentifier = $0.processIdentifier,
                  let bundleIdentifier = $0.bundleIdentifier else { return false }
            return processIdentifier != bundleIdentifier
        }
    }
}

func appUsageGroups(_ usages: [AppNetworkUsage]) -> [AppUsageGroup] {
    var buckets: [String: [AppNetworkUsage]] = [:]

    for usage in usages {
        // A true application bundle is grouped by bundle id. Processes that
        // cannot be attributed to an app remain individual system services.
        let key: String
        if usage.isSystemProcess {
            key = "system:\(usage.id)"
        } else {
            key = "app:\(appSelectionKey(usage))"
        }
        buckets[key, default: []].append(usage)
    }

    return buckets.values.map { members in
        let ordered = members.sorted {
            if $0.id == $0.bundleIdentifier && $1.id != $1.bundleIdentifier { return true }
            if $1.id == $1.bundleIdentifier && $0.id != $0.bundleIdentifier { return false }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let representative = ordered[0]
        let stableID = representative.isSystemProcess ? representative.id : appSelectionKey(representative)

        func sum(_ keyPath: KeyPath<AppNetworkUsage, UInt64>) -> UInt64 {
            ordered.reduce(UInt64(0)) { $0 &+ $1[keyPath: keyPath] }
        }

        let aggregate = AppNetworkUsage(
            id: stableID,
            displayName: representative.appDisplayName ?? representative.displayName,
            bundleIdentifier: representative.bundleIdentifier,
            processIdentifier: nil,
            appDisplayName: representative.appDisplayName ?? representative.displayName,
            icon: representative.icon,
            isSystemProcess: representative.isSystemProcess,
            isAppleApp: representative.isAppleApp,
            downloadBytesPerSecond: sum(\.downloadBytesPerSecond),
            uploadBytesPerSecond: sum(\.uploadBytesPerSecond),
            localDownloadBytesPerSecond: sum(\.localDownloadBytesPerSecond),
            localUploadBytesPerSecond: sum(\.localUploadBytesPerSecond),
            unknownDownloadBytesPerSecond: sum(\.unknownDownloadBytesPerSecond),
            unknownUploadBytesPerSecond: sum(\.unknownUploadBytesPerSecond),
            cumulativeDownloadBytes: sum(\.cumulativeDownloadBytes),
            cumulativeUploadBytes: sum(\.cumulativeUploadBytes),
            cumulativeLocalDownloadBytes: sum(\.cumulativeLocalDownloadBytes),
            cumulativeLocalUploadBytes: sum(\.cumulativeLocalUploadBytes),
            cumulativeUnknownDownloadBytes: sum(\.cumulativeUnknownDownloadBytes),
            cumulativeUnknownUploadBytes: sum(\.cumulativeUnknownUploadBytes),
            lastActiveAt: ordered.map(\.lastActiveAt).max() ?? representative.lastActiveAt
        )
        return AppUsageGroup(id: stableID, usage: aggregate, members: ordered)
    }
}


/// Collapse visually identical system-service rows for the ordinary app-first UI.
/// NetworkExtension can expose several low-level identities that resolve to the
/// same user-facing daemon name. Expert mode keeps the original rows instead.
func collapsedSystemServiceUsages(_ usages: [AppNetworkUsage]) -> [AppNetworkUsage] {
    var buckets: [String: [AppNetworkUsage]] = [:]
    for usage in usages {
        let key = usage.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        buckets[key, default: []].append(usage)
    }

    return buckets.values.map { members in
        guard let first = members.first else { fatalError("empty system-service bucket") }
        guard members.count > 1 else { return first }
        func sum(_ path: KeyPath<AppNetworkUsage, UInt64>) -> UInt64 {
            members.reduce(UInt64(0)) { $0 &+ $1[keyPath: path] }
        }
        return AppNetworkUsage(
            id: "system-display:\(first.displayName.lowercased())",
            displayName: first.displayName,
            bundleIdentifier: nil,
            processIdentifier: nil,
            appDisplayName: nil,
            icon: first.icon,
            isSystemProcess: true,
            isAppleApp: members.allSatisfy(\.isAppleApp),
            downloadBytesPerSecond: sum(\.downloadBytesPerSecond),
            uploadBytesPerSecond: sum(\.uploadBytesPerSecond),
            localDownloadBytesPerSecond: sum(\.localDownloadBytesPerSecond),
            localUploadBytesPerSecond: sum(\.localUploadBytesPerSecond),
            unknownDownloadBytesPerSecond: sum(\.unknownDownloadBytesPerSecond),
            unknownUploadBytesPerSecond: sum(\.unknownUploadBytesPerSecond),
            cumulativeDownloadBytes: sum(\.cumulativeDownloadBytes),
            cumulativeUploadBytes: sum(\.cumulativeUploadBytes),
            cumulativeLocalDownloadBytes: sum(\.cumulativeLocalDownloadBytes),
            cumulativeLocalUploadBytes: sum(\.cumulativeLocalUploadBytes),
            cumulativeUnknownDownloadBytes: sum(\.cumulativeUnknownDownloadBytes),
            cumulativeUnknownUploadBytes: sum(\.cumulativeUnknownUploadBytes),
            lastActiveAt: members.map(\.lastActiveAt).max() ?? first.lastActiveAt
        )
    }
}

func appGroupMatchesSelection(_ group: AppUsageGroup, selectedIDs: Set<String>) -> Bool {
    selectedIDs.contains(group.id) || group.members.contains { isAppUsageSelected($0, selectedIDs: selectedIDs) }
}

func appGroupMatchesHidden(_ group: AppUsageGroup, hiddenIDs: Set<String>) -> Bool {
    hiddenIDs.contains(group.id) || group.members.contains { hiddenIDs.contains($0.id) }
}

/// Lightweight in-memory history used only to decide whether an app has stayed
/// below the user's low-activity amount for the chosen time window. It reuses the
/// Network Extension cumulative counters; it does not create another network poll.
struct LowActivityWindowTracker {
    private struct Point {
        let date: Date
        let total: UInt64
    }

    private var points: [String: [Point]] = [:]

    mutating func reset() {
        points.removeAll(keepingCapacity: true)
    }

    mutating func record(usages: [AppNetworkUsage], at now: Date, retention: TimeInterval) {
        let keep = max(60, retention + 60)
        let minSampleSpacing = max(1, min(30, keep / 600))
        let groups = appUsageGroups(usages.filter { !$0.isSystemProcess })
        let activeIDs = Set(groups.map(\.id))

        for group in groups {
            let total = group.usage.cumulativeDownloadBytes &+ group.usage.cumulativeUploadBytes
            var series = points[group.id] ?? []
            if let last = series.last, now.timeIntervalSince(last.date) < minSampleSpacing {
                series[series.count - 1] = Point(date: now, total: total)
            } else {
                series.append(Point(date: now, total: total))
            }
            let cutoff = now.addingTimeInterval(-keep)
            if let firstKept = series.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 {
                // Keep one point before the cutoff so a delta across the boundary
                // remains computable without keeping the full old history.
                series.removeFirst(max(0, firstKept - 1))
            }
            points[group.id] = series
        }

        // Drop apps that have been absent longer than the retained window.
        for id in Array(points.keys) where !activeIDs.contains(id) {
            if let last = points[id]?.last, now.timeIntervalSince(last.date) > keep {
                points.removeValue(forKey: id)
            }
        }
    }

    func transferredBytes(for groupID: String, duration: TimeInterval, now: Date) -> UInt64? {
        guard duration > 0, let series = points[groupID], let latest = series.last else { return nil }
        let cutoff = now.addingTimeInterval(-duration)
        guard let baseline = series.last(where: { $0.date <= cutoff }) else {
            // Do not classify an app as low activity until the full requested
            // observation window has actually elapsed.
            return nil
        }
        guard latest.total >= baseline.total else { return nil }
        return latest.total - baseline.total
    }
}


/// When local SMB/NAS traffic is deliberately kept on the report-only safety path,
/// Network Extension may not have an attributable per-app byte counter even though
/// the interface clearly carries a large non-Internet transfer. Surface that truth
/// as a generic local-activity row instead of inventing an owning app.
func conservativeLocalNetworkFallbackUsage(interface: NetworkSnapshot,
                                           usages: [AppNetworkUsage],
                                           displayName: String) -> AppNetworkUsage? {
    let exactLocalDown = usages.reduce(UInt64(0)) { $0 &+ $1.localDownloadBytesPerSecond }
    let exactLocalUp = usages.reduce(UInt64(0)) { $0 &+ $1.localUploadBytesPerSecond }

    let knownInternetDown = usages.reduce(UInt64(0)) { $0 &+ $1.internetDownloadBytesPerSecond }
    let knownInternetUp = usages.reduce(UInt64(0)) { $0 &+ $1.internetUploadBytesPerSecond }
    let knownUnknownDown = usages.reduce(UInt64(0)) { $0 &+ $1.unknownDownloadBytesPerSecond }
    let knownUnknownUp = usages.reduce(UInt64(0)) { $0 &+ $1.unknownUploadBytesPerSecond }

    let accountedDown = knownInternetDown &+ knownUnknownDown &+ exactLocalDown
    let accountedUp = knownInternetUp &+ knownUnknownUp &+ exactLocalUp
    let residualDown = interface.downloadBytesPerSecond > accountedDown ? interface.downloadBytesPerSecond - accountedDown : 0
    let residualUp = interface.uploadBytesPerSecond > accountedUp ? interface.uploadBytesPerSecond - accountedUp : 0

    // Keep this deliberately conservative so ordinary measurement jitter does not
    // masquerade as local activity. NAS/SMB transfers normally clear this easily.
    guard residualDown &+ residualUp >= 64 * 1024 else { return nil }
    let icon = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: nil)
        ?? NSWorkspace.shared.icon(for: .folder)
    return AppNetworkUsage(id: "nemaneem.local.aggregate",
                           displayName: displayName,
                           bundleIdentifier: nil,
                           processIdentifier: nil,
                           appDisplayName: nil,
                           icon: icon,
                           isSystemProcess: true,
                           isAppleApp: false,
                           downloadBytesPerSecond: residualDown,
                           uploadBytesPerSecond: residualUp,
                           localDownloadBytesPerSecond: residualDown,
                           localUploadBytesPerSecond: residualUp,
                           cumulativeDownloadBytes: 0,
                           cumulativeUploadBytes: 0,
                           cumulativeLocalDownloadBytes: 0,
                           cumulativeLocalUploadBytes: 0,
                           lastActiveAt: Date())
}
