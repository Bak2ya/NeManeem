import Combine
import Foundation
import UserNotifications

@MainActor
final class UsageRecorder: ObservableObject {
    @Published private(set) var buckets: [UsageBucket] = []
    @Published private(set) var storedFileSize: UInt64 = 0
    @Published private(set) var dataUsageRecords: [DataUsageRecord] = []
    @Published private(set) var sessionRecords: [UsageSessionRecord] = []
    @Published private(set) var sessionPaused = false
    @Published private(set) var persistedStateLoaded = false

    private let settings: SettingsStore
    private let interfaceMonitor: NetworkInterfaceMonitor
    private let appTrafficMonitor: AppTrafficMonitor
    private let firewallController: FirewallController
    private var cancellables = Set<AnyCancellable>()
    private var previousSnapshot: NetworkSnapshot?
    private var previousProcessTotals: [String: AppBytePair] = [:]
    private var previousDetailProcessTotals: [String: AppBytePair] = [:]
    private var lastPersist = Date.distantPast
    private let calendar = Calendar.current
    private let alertDefaults = UserDefaults.standard
    private var appPeriodCache: [StatusColumn: [String: AppBytePair]] = [:]
    private var totalPeriodCache: [StatusColumn: AppBytePair] = [:]
    private var activeSessionState: ActiveUsageSessionState?
    private var sessionScheduleTask: Task<Void, Never>?
    private var persistedStateLoadStarted = false
    // User-triggered deletion can happen while deferred launch I/O is still in flight.
    // These flags prevent an older disk snapshot from being applied after the user
    // has just cleared that category.
    private var discardDeferredHistory = false
    private var discardDeferredDataUsageRecords = false
    private var discardDeferredSessionRecords = false
    private var discardDeferredActiveSession = false

    init(settings: SettingsStore,
         interfaceMonitor: NetworkInterfaceMonitor,
         appTrafficMonitor: AppTrafficMonitor,
         firewallController: FirewallController) {
        self.settings = settings
        self.interfaceMonitor = interfaceMonitor
        self.appTrafficMonitor = appTrafficMonitor
        self.firewallController = firewallController

        interfaceMonitor.$snapshot
            .sink { [weak self] snapshot in self?.consume(snapshot) }
            .store(in: &cancellables)

        appTrafficMonitor.$usages
            .sink { [weak self] usages in self?.consumeAppUsages(usages) }
            .store(in: &cancellables)

        settings.$recordingMode
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.previousProcessTotals = [:]
                self.previousDetailProcessTotals = [:]
                self.updateAppTrafficRecordingDemand()
                self.evaluateDataLimit()
            }
            .store(in: &cancellables)

        settings.$resourceMode
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.previousProcessTotals = [:]
                self.previousDetailProcessTotals = [:]
                self.updateAppTrafficRecordingDemand()
            }
            .store(in: &cancellables)

        settings.$dataLimitTrafficScope
            .dropFirst()
            .sink { [weak self] _ in self?.updateAppTrafficRecordingDemand() }
            .store(in: &cancellables)

        settings.$separateLocalTraffic
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateAppTrafficRecordingDemand()
                self.evaluateDataLimit()
            }
            .store(in: &cancellables)

        settings.$processDetailRecordingEnabled
            .dropFirst()
            .sink { [weak self] _ in self?.previousDetailProcessTotals = [:] }
            .store(in: &cancellables)

        settings.$historyRetentionDays
            .dropFirst()
            .sink { [weak self] _ in self?.trimAndPersist(force: true) }
            .store(in: &cancellables)

        settings.$dataLimitEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.updateAppTrafficRecordingDemand()
                if enabled { self.evaluateDataLimit() }
                else { self.firewallController.setDataLimitInternetBlocked(false) }
            }
            .store(in: &cancellables)

        settings.$dataLimitReachedAction
            .dropFirst()
            .sink { [weak self] action in
                guard let self else { return }
                if action == .continueData { self.firewallController.setDataLimitInternetBlocked(false) }
                else { self.evaluateDataLimit() }
            }
            .store(in: &cancellables)

        // Limit edits should take effect immediately rather than waiting for the
        // next traffic sample or the 30-second idle timer. This is especially
        // important when switching the target network or pressing “From Now”
        // while a previous cycle has already blocked Internet access.
        settings.$dataLimitNetworkTargetMode
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitNetworkIdentifier
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitStartDate
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitEndDate
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitPeriodMode
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitPeriodValue
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitPeriodUnit
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitEndBehavior
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitValue
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)
        settings.$dataLimitUnit
            .dropFirst()
            .sink { [weak self] _ in self?.evaluateDataLimit() }
            .store(in: &cancellables)

        // Data-limit state must advance even when no network bytes are flowing.
        // This also makes shared repeat warnings fire on time and guarantees a
        // limit block is released automatically when the next cycle begins.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self, self.settings.dataLimitEnabled else { return }
                self.archiveCompletedDataCycleIfNeeded(now: now)
                self.evaluateDataLimit()
            }
            .store(in: &cancellables)
    }


    private struct DeferredLoadedState: @unchecked Sendable {
        let buckets: [UsageBucket]
        let dataUsageRecords: [DataUsageRecord]
        let sessionRecords: [UsageSessionRecord]
        let activeSessionState: ActiveUsageSessionState?
        let historyFileSize: UInt64
    }

    /// Build 50 launch rule: disk history is restored only after the visible menu-bar
    /// surface exists. The I/O and JSON decoding run at utility priority so a large
    /// history file cannot make NeManeem look as if it failed to launch.
    func loadPersistedStateAfterLaunch() async {
        guard !persistedStateLoaded, !persistedStateLoadStarted else { return }
        persistedStateLoadStarted = true
        let loaded = await Task.detached(priority: .utility) {
            Self.loadPersistedStateFromDisk()
        }.value
        if !discardDeferredHistory {
            buckets = loaded.buckets
            storedFileSize = loaded.historyFileSize
        }
        if !discardDeferredDataUsageRecords {
            dataUsageRecords = loaded.dataUsageRecords
        }
        if !discardDeferredSessionRecords {
            sessionRecords = loaded.sessionRecords
        }
        if !discardDeferredActiveSession {
            activeSessionState = loaded.activeSessionState
            sessionPaused = loaded.activeSessionState?.paused ?? false
            reconcileSessionStateAfterDeferredLoad()
            restoreSessionScheduleAfterDeferredLoad()
        }
        persistedStateLoaded = true
        persistedStateLoadStarted = false
        evaluateDataLimit()
    }

    func activateRuntimeAfterLaunch() {
        updateAppTrafficRecordingDemand()
        evaluateDataLimit()
    }

    /// Stops recorder subscriptions/timers for the remainder of this process.
    /// The stored settings/records are left untouched unless the user separately
    /// chooses to delete them in the safe-removal flow.
    func prepareForRemoval() {
        sessionScheduleTask?.cancel()
        sessionScheduleTask = nil
        cancellables.removeAll()
        previousSnapshot = nil
        previousProcessTotals.removeAll(keepingCapacity: false)
        previousDetailProcessTotals.removeAll(keepingCapacity: false)
        appPeriodCache.removeAll(keepingCapacity: false)
        totalPeriodCache.removeAll(keepingCapacity: false)
        appTrafficMonitor.setDemand(.recording, active: false)
    }

    private func updateAppTrafficRecordingDemand() {
        let normalPerAppRecording = settings.recordingMode == .perApp && settings.resourceMode != .austerity
        let austerityInternetLimit = settings.resourceMode == .austerity &&
            settings.dataLimitEnabled && settings.effectiveDataLimitTrafficScope == .internetOnly
        appTrafficMonitor.setDemand(.recording, active: normalPerAppRecording || austerityInternetLimit)
    }

    func clearTemporaryCaches() {
        appPeriodCache.removeAll(keepingCapacity: false)
        totalPeriodCache.removeAll(keepingCapacity: false)
        previousSnapshot = nil
        previousProcessTotals.removeAll(keepingCapacity: false)
        previousDetailProcessTotals.removeAll(keepingCapacity: false)
    }

    func clearDataUsageRecords() {
        discardDeferredDataUsageRecords = true
        dataUsageRecords.removeAll()
        persistDataUsageRecords()
    }

    func deleteDataUsageRecord(id: UUID) {
        guard dataUsageRecords.contains(where: { $0.id == id }) else { return }
        discardDeferredDataUsageRecords = true
        dataUsageRecords.removeAll { $0.id == id }
        persistDataUsageRecords()
    }

    private func reconcileSessionStateAfterDeferredLoad() {
        if settings.sessionEnabled && activeSessionState == nil {
            if settings.sessionStartMode == .scheduled {
                // A scheduled active session must have an archive state. If it does
                // not, do not invent traffic/time that was never recorded.
                settings.sessionEnabled = false
                sessionPaused = false
            } else {
                activeSessionState = ActiveUsageSessionState(startedAt: settings.sessionStartDate,
                                                             paused: false,
                                                             segments: [UsageSessionSegment(start: settings.sessionStartDate, end: nil)])
                sessionPaused = false
            }
        } else if !settings.sessionEnabled {
            activeSessionState = nil
            sessionPaused = false
        }
    }

    private nonisolated static func loadPersistedStateFromDisk() -> DeferredLoadedState {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return DeferredLoadedState(buckets: [], dataUsageRecords: [], sessionRecords: [], activeSessionState: nil, historyFileSize: 0)
        }
        let folder = base.appendingPathComponent("NeManeem", isDirectory: true)
        let historyURL = folder.appendingPathComponent("usage-history.json")
        let recordsURL = folder.appendingPathComponent("data-usage-records.json")
        let sessionsURL = folder.appendingPathComponent("usage-sessions.json")
        let decoder = JSONDecoder()

        let buckets: [UsageBucket]
        if let data = try? Data(contentsOf: historyURL), let decoded = try? decoder.decode([UsageBucket].self, from: data) {
            buckets = decoded
        } else { buckets = [] }

        let records: [DataUsageRecord]
        if let data = try? Data(contentsOf: recordsURL), let decoded = try? decoder.decode([DataUsageRecord].self, from: data) {
            records = decoded
        } else { records = [] }

        let archive: SessionArchive?
        if let data = try? Data(contentsOf: sessionsURL) {
            archive = try? decoder.decode(SessionArchive.self, from: data)
        } else { archive = nil }
        let size = UInt64((try? historyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return DeferredLoadedState(buckets: buckets,
                                   dataUsageRecords: records,
                                   sessionRecords: archive?.records ?? [],
                                   activeSessionState: archive?.active,
                                   historyFileSize: size)
    }

    var sessionTotal: AppBytePair {
        guard settings.sessionEnabled, let state = activeSessionState else { return AppBytePair() }
        return total(for: state.segments, now: Date())
    }

    var sessionElapsed: TimeInterval {
        guard settings.sessionEnabled, let state = activeSessionState else { return 0 }
        let now = Date()
        return state.segments.reduce(0) { partial, segment in
            partial + max(0, (segment.end ?? now).timeIntervalSince(segment.start))
        }
    }

    var knownNetworks: [RecordedNetworkIdentity] {
        var values: [String: RecordedNetworkIdentity] = [:]
        for bucket in buckets {
            guard let id = bucket.networkIdentifier, !id.isEmpty else { continue }
            let name = bucket.networkDisplayName?.isEmpty == false ? bucket.networkDisplayName! : id
            let reliable = bucket.networkIdentityReliable ?? false
            if let previous = values[id] {
                values[id] = RecordedNetworkIdentity(id: id, displayName: name, reliable: previous.reliable || reliable)
            } else {
                values[id] = RecordedNetworkIdentity(id: id, displayName: name, reliable: reliable)
            }
        }
        let current = interfaceMonitor.snapshot
        if !current.networkIdentifier.isEmpty {
            values[current.networkIdentifier] = RecordedNetworkIdentity(id: current.networkIdentifier,
                                                                         displayName: current.networkDisplayName.isEmpty ? current.networkIdentifier : current.networkDisplayName,
                                                                         reliable: current.networkIdentityReliable)
        }
        return values.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var currentCycleTotal: AppBytePair {
        let now = Date()
        let bounds = currentDataCycleBounds(at: now)
        guard now >= bounds.start else { return AppBytePair() }
        let recordedEnd = min(now, bounds.end)
        return scopedTotal(from: bounds.start, to: recordedEnd)
    }

    func appRecommendationStats(from start: Date, to end: Date) -> [AppUsageRecommendationStat] {
        guard end >= start else { return [] }
        var totals: [String: UInt64] = [:]
        var activeDays: [String: Set<Date>] = [:]
        for bucket in buckets where bucket.start >= start && bucket.start <= end {
            let day = calendar.startOfDay(for: bucket.start)
            for (identifier, value) in bucket.apps {
                let bytes = value.download &+ value.upload
                guard bytes > 0 else { continue }
                totals[identifier, default: 0] &+= bytes
                activeDays[identifier, default: []].insert(day)
            }
        }
        return totals.map { identifier, total in
            AppUsageRecommendationStat(id: identifier,
                                       totalBytes: total,
                                       activeDays: activeDays[identifier]?.count ?? 0)
        }
    }

    func appTotals(from start: Date, to end: Date, networkIdentifier: String? = nil) -> [String: AppBytePair] {
        var result: [String: AppBytePair] = [:]
        for bucket in buckets where bucket.start >= start && bucket.start <= end {
            if let networkIdentifier, bucket.networkIdentifier != networkIdentifier { continue }
            for (identifier, value) in bucket.apps {
                var pair = result[identifier] ?? AppBytePair()
                pair.download &+= value.download
                pair.upload &+= value.upload
                pair.localDownload &+= value.localDownload
                pair.localUpload &+= value.localUpload
                pair.unknownDownload &+= value.unknownDownload
                pair.unknownUpload &+= value.unknownUpload
                result[identifier] = pair
            }
        }
        return result
    }

    func processTotals(from start: Date,
                       to end: Date,
                       appIdentifier: String? = nil,
                       networkIdentifier: String? = nil) -> [String: ProcessUsageHistoryValue] {
        var result: [String: ProcessUsageHistoryValue] = [:]
        for bucket in buckets where bucket.start >= start && bucket.start <= end {
            if let networkIdentifier, bucket.networkIdentifier != networkIdentifier { continue }
            guard let processes = bucket.processes else { continue }
            for (identifier, value) in processes {
                if let appIdentifier {
                    let belongs = value.bundleIdentifier == appIdentifier || identifier == appIdentifier
                    if !belongs { continue }
                }
                var pair = result[identifier]?.bytes ?? AppBytePair()
                pair.download &+= value.bytes.download
                pair.upload &+= value.bytes.upload
                pair.localDownload &+= value.bytes.localDownload
                pair.localUpload &+= value.bytes.localUpload
                pair.unknownDownload &+= value.bytes.unknownDownload
                pair.unknownUpload &+= value.bytes.unknownUpload
                result[identifier] = ProcessUsageHistoryValue(displayName: value.displayName,
                                                               bundleIdentifier: value.bundleIdentifier,
                                                               bytes: pair)
            }
        }
        return result
    }

    func hasProcessDetailHistory(from start: Date, to end: Date) -> Bool {
        buckets.contains { bucket in
            bucket.start >= start && bucket.start <= end && !(bucket.processes?.isEmpty ?? true)
        }
    }

    /// Whole recorded value for a status-table usage column. This intentionally
    /// uses the recorder's total buckets rather than summing app rows so the
    /// `Overall` row also includes traffic that could not be attributed to an app.
    func total(for column: StatusColumn, now: Date = Date()) -> AppBytePair {
        switch column {
        case .today, .week, .month:
            if let cached = totalPeriodCache[column] { return cached }
            let start: Date
            switch column {
            case .today:
                start = calendar.startOfDay(for: now)
            case .week:
                start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            case .month:
                start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            default:
                return AppBytePair()
            }
            let value = total(from: start, to: now)
            totalPeriodCache[column] = value
            return value
        case .session:
            return sessionTotal
        case .dataCycle:
            return currentCycleTotal
        case .process, .download, .upload, .block:
            return AppBytePair()
        }
    }

    func appTotals(for column: StatusColumn, now: Date = Date()) -> [String: AppBytePair] {
        if let cached = appPeriodCache[column] { return cached }
        let start: Date
        switch column {
        case .today:
            start = calendar.startOfDay(for: now)
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .session:
            guard settings.sessionEnabled, let state = activeSessionState else { return [:] }
            let values = appTotals(for: state.segments, now: now)
            appPeriodCache[column] = values
            return values
        case .dataCycle:
            start = currentDataCycleStart(at: now)
        default:
            return [:]
        }
        let networkID: String? = column == .dataCycle && settings.dataLimitNetworkTargetMode == .selectedNetwork
            ? settings.dataLimitNetworkIdentifier
            : nil
        let values = appTotals(from: start, to: now, networkIdentifier: networkID)
        appPeriodCache[column] = values
        return values
    }

    func processTotals(for column: StatusColumn, now: Date = Date()) -> [String: ProcessUsageHistoryValue] {
        let start: Date
        switch column {
        case .today:
            start = calendar.startOfDay(for: now)
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .session:
            guard settings.sessionEnabled, let state = activeSessionState else { return [:] }
            return processTotals(for: state.segments, now: now)
        case .dataCycle:
            start = currentDataCycleStart(at: now)
        default:
            return [:]
        }
        let networkID: String? = column == .dataCycle && settings.dataLimitNetworkTargetMode == .selectedNetwork
            ? settings.dataLimitNetworkIdentifier
            : nil
        return processTotals(from: start, to: now, networkIdentifier: networkID)
    }

    func currentDataCycleStart(at date: Date = Date()) -> Date {
        currentDataCycleBounds(at: date).start
    }

    func currentDataCycleBounds(at now: Date) -> (start: Date, end: Date) {
        let initialStart = settings.dataLimitStartDate
        let initialEnd = initialDataLimitEnd()

        if now < initialEnd || settings.dataLimitEndBehavior == .stop {
            return (initialStart, initialEnd)
        }

        switch settings.dataLimitEndBehavior {
        case .stop:
            return (initialStart, initialEnd)
        case .repeatSame:
            if settings.dataLimitPeriodMode == .duration {
                let value = max(1, settings.dataLimitPeriodValue)
                var index = 0
                var start = initialStart
                var end = initialEnd
                while now >= end && index < 2400 {
                    index += 1
                    switch settings.dataLimitPeriodUnit {
                    case .days:
                        start = calendar.date(byAdding: .day, value: value * index, to: initialStart)
                            ?? initialStart.addingTimeInterval(TimeInterval(value * index) * 86400)
                        end = calendar.date(byAdding: .day, value: value * (index + 1), to: initialStart)
                            ?? initialStart.addingTimeInterval(TimeInterval(value * (index + 1)) * 86400)
                    case .months:
                        // Always calculate from the original anchor so a Jan 31 cycle
                        // can fall back in February and return to the 31st in March.
                        start = calendar.date(byAdding: .month, value: value * index, to: initialStart)
                            ?? initialStart.addingTimeInterval(TimeInterval(value * index) * 30 * 86400)
                        end = calendar.date(byAdding: .month, value: value * (index + 1), to: initialStart)
                            ?? initialStart.addingTimeInterval(TimeInterval(value * (index + 1)) * 30 * 86400)
                    }
                }
                return (start, end)
            }

            let duration = max(60, initialEnd.timeIntervalSince(initialStart))
            let index = max(0, Int(floor(now.timeIntervalSince(initialStart) / duration)))
            let start = initialStart.addingTimeInterval(TimeInterval(index) * duration)
            return (start, start.addingTimeInterval(duration))
        case .switchToMonthly:
            // After the initial period, keep management continuous and reset on
            // the user-selected day of each month. The first post-initial cycle can
            // therefore be a short bridge until the next selected monthly boundary.
            let firstBoundary = monthlyBoundary(after: initialEnd, day: settings.dataLimitMonthlyStartDay)
            if now < firstBoundary { return (initialEnd, firstBoundary) }
            var start = firstBoundary
            var end = monthlyBoundary(after: start, day: settings.dataLimitMonthlyStartDay)
            var safety = 0
            while now >= end && safety < 2400 {
                safety += 1
                start = end
                end = monthlyBoundary(after: start, day: settings.dataLimitMonthlyStartDay)
            }
            return (start, end)
        }
    }

    var recentDataUsageRecords: [DataUsageRecord] {
        Array(dataUsageRecords.sorted { $0.start > $1.start }.prefix(12))
    }

    func total(from start: Date, to end: Date) -> AppBytePair {
        buckets.reduce(into: AppBytePair()) { result, bucket in
            guard bucket.start >= start && bucket.start <= end else { return }
            result.download &+= bucket.download
            result.upload &+= bucket.upload
        }
    }

    func points(from start: Date, to end: Date, intervalMinutes: Int) -> [UsagePoint] {
        let seconds = TimeInterval(max(1, intervalMinutes) * 60)
        var groups: [Date: AppBytePair] = [:]
        for bucket in buckets where bucket.start >= start && bucket.start <= end {
            let epoch = bucket.start.timeIntervalSince1970
            let groupDate = Date(timeIntervalSince1970: floor(epoch / seconds) * seconds)
            var pair = groups[groupDate] ?? AppBytePair()
            pair.download &+= bucket.download
            pair.upload &+= bucket.upload
            groups[groupDate] = pair
        }
        return groups.keys.sorted().map { date in
            let value = groups[date] ?? AppBytePair()
            return UsagePoint(start: date, download: value.download, upload: value.upload)
        }
    }

    // MARK: - Session stopwatch

    @discardableResult
    func startSession() -> Bool {
        // A session depends on the same trusted usage-recording source as normal history.
        // Never imply measurement is active while recording itself is disabled.
        guard settings.recordingMode != .off else { return false }
        // A pending reservation is a distinct user intent. Do not silently replace
        // it with an immediate session; the UI exposes an explicit reservation cancel.
        guard !hasPendingSessionSchedule else { return false }
        sessionScheduleTask?.cancel()
        sessionScheduleTask = nil
        let now = Date()
        settings.sessionEnabled = true
        settings.sessionStartDate = now
        settings.sessionStartMode = .now
        sessionPaused = false
        activeSessionState = ActiveUsageSessionState(startedAt: now,
                                                     paused: false,
                                                     segments: [UsageSessionSegment(start: now, end: nil)])
        appPeriodCache.removeAll(keepingCapacity: true)
        totalPeriodCache.removeAll(keepingCapacity: true)
        persistSessions()
        objectWillChange.send()
        return true
    }

    func pauseSession() {
        guard settings.sessionEnabled, var state = activeSessionState, !state.paused else { return }
        let now = Date()
        if let index = state.segments.indices.last, state.segments[index].end == nil {
            state.segments[index].end = now
        }
        state.paused = true
        activeSessionState = state
        sessionPaused = true
        appPeriodCache.removeAll(keepingCapacity: true)
        totalPeriodCache.removeAll(keepingCapacity: true)
        persistSessions()
        objectWillChange.send()
    }

    func resumeSession() {
        guard settings.sessionEnabled, var state = activeSessionState, state.paused else { return }
        state.segments.append(UsageSessionSegment(start: Date(), end: nil))
        state.paused = false
        activeSessionState = state
        sessionPaused = false
        appPeriodCache.removeAll(keepingCapacity: true)
        totalPeriodCache.removeAll(keepingCapacity: true)
        persistSessions()
        objectWillChange.send()
    }

    @discardableResult
    func finishSession(name: String? = nil) -> UsageSessionRecord? {
        guard settings.sessionEnabled else { return nil }
        let end = Date()
        let scheduled = settings.sessionStartMode == .scheduled
        let record = finishSessionInternal(name: name, end: end)
        if scheduled {
            sessionScheduleTask?.cancel()
            sessionScheduleTask = nil
            settings.sessionStartMode = .now
        }
        return record
    }

    @discardableResult
    private func finishSessionInternal(name: String? = nil, end: Date) -> UsageSessionRecord? {
        guard settings.sessionEnabled, var state = activeSessionState else { return nil }
        if !state.paused, let index = state.segments.indices.last, state.segments[index].end == nil {
            state.segments[index].end = end
        }
        let pair = total(for: state.segments, now: end)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = UsageSessionRecord(name: (trimmedName?.isEmpty == false ? trimmedName : nil),
                                        start: state.startedAt,
                                        end: end,
                                        download: pair.download,
                                        upload: pair.upload)
        sessionRecords.append(record)
        settings.sessionEnabled = false
        sessionPaused = false
        activeSessionState = nil
        appPeriodCache.removeAll(keepingCapacity: true)
        totalPeriodCache.removeAll(keepingCapacity: true)
        persistSessions()
        objectWillChange.send()
        return record
    }

    func deleteSessionRecord(id: UUID) {
        sessionRecords.removeAll { $0.id == id }
        persistSessions()
    }

    func clearSessionRecords() {
        discardDeferredSessionRecords = true
        sessionRecords.removeAll()
        persistSessions()
    }

    func clearAllSessionData() {
        discardDeferredSessionRecords = true
        discardDeferredActiveSession = true
        sessionScheduleTask?.cancel()
        sessionScheduleTask = nil
        settings.sessionEnabled = false
        settings.sessionStartMode = .now
        sessionRecords.removeAll()
        activeSessionState = nil
        sessionPaused = false
        persistSessions()
        objectWillChange.send()
    }

    var hasPendingSessionSchedule: Bool {
        settings.sessionStartMode == .scheduled && !settings.sessionEnabled
    }

    func scheduleSession(start: Date, end: Date) {
        guard !settings.sessionEnabled else { return }
        let normalizedStart = max(start, Date().addingTimeInterval(1))
        let normalizedEnd = max(end, normalizedStart.addingTimeInterval(60))
        sessionScheduleTask?.cancel()
        settings.scheduledSessionStartDate = normalizedStart
        settings.scheduledSessionEndDate = normalizedEnd
        settings.sessionStartMode = .scheduled
        armPendingSessionSchedule()
        objectWillChange.send()
    }

    /// Adds or changes an automatic end time for a session that is already running.
    /// Reuses the same persisted scheduled-end state so the reservation survives an
    /// app relaunch without introducing a second competing session timer.
    func scheduleActiveSessionEnd(at date: Date) {
        guard settings.sessionEnabled, let state = activeSessionState else { return }
        let normalizedEnd = max(date, Date().addingTimeInterval(60))
        settings.scheduledSessionStartDate = state.startedAt
        settings.scheduledSessionEndDate = normalizedEnd
        settings.sessionStartMode = .scheduled
        armScheduledEnd()
        objectWillChange.send()
    }

    /// Compatibility helper for older callers that only supplied a start time.
    func scheduleSession(at date: Date) {
        scheduleSession(start: date, end: date.addingTimeInterval(3600))
    }

    func cancelScheduledSession() {
        guard settings.sessionStartMode == .scheduled else { return }
        sessionScheduleTask?.cancel()
        sessionScheduleTask = nil
        if settings.sessionEnabled {
            _ = finishSession()
        } else {
            settings.sessionStartMode = .now
            objectWillChange.send()
        }
    }

    private func restoreSessionScheduleAfterDeferredLoad() {
        guard settings.sessionStartMode == .scheduled else { return }
        let now = Date()
        if settings.sessionEnabled, activeSessionState != nil {
            if now >= settings.scheduledSessionEndDate {
                finishScheduledSession(at: settings.scheduledSessionEndDate)
            } else {
                armScheduledEnd()
            }
            return
        }
        guard !settings.sessionEnabled else { return }
        if now >= settings.scheduledSessionStartDate {
            // The app was not running at the scheduled start. Never fabricate the
            // missing interval or pretend it was measured.
            settings.sessionStartMode = .now
            postSessionNotification(titleKey: "sessionScheduleMissedTitle", bodyKey: "sessionScheduleMissedBody")
        } else {
            armPendingSessionSchedule()
        }
    }

    private func armPendingSessionSchedule() {
        sessionScheduleTask?.cancel()
        let start = settings.scheduledSessionStartDate
        sessionScheduleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = max(0, start.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled,
                  self.settings.sessionStartMode == .scheduled,
                  !self.settings.sessionEnabled else { return }
            self.startScheduledSession()
        }
    }

    private func startScheduledSession() {
        let now = Date()
        guard settings.sessionStartMode == .scheduled,
              !settings.sessionEnabled,
              now < settings.scheduledSessionEndDate else { return }
        settings.sessionEnabled = true
        settings.sessionStartDate = now
        sessionPaused = false
        activeSessionState = ActiveUsageSessionState(startedAt: now,
                                                     paused: false,
                                                     segments: [UsageSessionSegment(start: now, end: nil)])
        appPeriodCache.removeAll(keepingCapacity: true)
        totalPeriodCache.removeAll(keepingCapacity: true)
        persistSessions()
        postSessionNotification(titleKey: "sessionScheduleStartedTitle", bodyKey: "sessionScheduleStartedBody")
        objectWillChange.send()
        armScheduledEnd()
    }

    private func armScheduledEnd() {
        sessionScheduleTask?.cancel()
        let end = settings.scheduledSessionEndDate
        sessionScheduleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = max(0, end.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled,
                  self.settings.sessionStartMode == .scheduled,
                  self.settings.sessionEnabled else { return }
            self.finishScheduledSession(at: end)
        }
    }

    private func finishScheduledSession(at end: Date) {
        sessionScheduleTask?.cancel()
        sessionScheduleTask = nil
        _ = finishSessionInternal(end: end)
        settings.sessionStartMode = .now
        postSessionNotification(titleKey: "sessionScheduleFinishedTitle", bodyKey: "sessionScheduleFinishedBody")
    }

    private func postSessionNotification(titleKey: String, bodyKey: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text(titleKey, language: settings.language)
        content.body = L10n.text(bodyKey, language: settings.language)
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Data and export

    func clearHistory() {
        discardDeferredHistory = true
        buckets = []
        appPeriodCache.removeAll()
        totalPeriodCache.removeAll()
        persist()
    }

    func exportCSV(from start: Date, to end: Date, intervalMinutes: Int, destination: URL) throws {
        let formatter = ISO8601DateFormatter()
        var text = "timestamp,scope,app_identifier,network,download_bytes,upload_bytes,total_bytes\n"
        for row in exportRows(from: start, to: end) {
            let fields = [formatter.string(from: row.start), row.scope, row.appIdentifier ?? "", row.networkName ?? ""]
                .map(csvField).joined(separator: ",")
            text += "\(fields),\(row.download),\(row.upload),\(row.download + row.upload)\n"
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    func exportXLSX(from start: Date, to end: Date, intervalMinutes: Int, includeSummary: Bool = true, destination: URL) throws {
        let aggregate = total(from: start, to: end)
        try XLSXExporter.export(rows: exportRows(from: start, to: end), total: aggregate, start: start, end: end, includeSummary: includeSummary, destination: destination)
    }

    func exportDataUsageRecordsCSV(_ records: [DataUsageRecord], destination: URL) throws {
        let formatter = ISO8601DateFormatter()
        var text = "start,end,download_bytes,upload_bytes,total_bytes,limit_bytes,usage_percent,network,label,limit_reached\n"
        for record in records.sorted(by: { $0.start > $1.start }) {
            let percent = record.limitBytes > 0 ? (Double(record.total) / Double(record.limitBytes)) * 100.0 : 0
            let fields = [
                formatter.string(from: record.start),
                formatter.string(from: record.end),
                String(record.download),
                String(record.upload),
                String(record.total),
                String(record.limitBytes),
                String(format: "%.2f", percent),
                record.networkDisplayName ?? "",
                record.label ?? "",
                record.limitBytes > 0 && record.total >= record.limitBytes ? "true" : "false"
            ].map(csvField).joined(separator: ",")
            text += fields + "\n"
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    func exportDataUsageRecordsXLSX(_ records: [DataUsageRecord], destination: URL) throws {
        try XLSXExporter.exportDataUsageRecords(records: records.sorted(by: { $0.start > $1.start }), destination: destination)
    }

    func exportSessionRecordsCSV(_ records: [UsageSessionRecord], destination: URL) throws {
        let formatter = ISO8601DateFormatter()
        var text = "name,start,end,duration_seconds,download_bytes,upload_bytes,total_bytes\n"
        for record in records.sorted(by: { $0.end > $1.end }) {
            let fields = [
                record.name ?? "",
                formatter.string(from: record.start),
                formatter.string(from: record.end),
                String(format: "%.3f", record.duration),
                String(record.download),
                String(record.upload),
                String(record.total)
            ].map(csvField).joined(separator: ",")
            text += fields + "\n"
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    func exportSessionRecordsXLSX(_ records: [UsageSessionRecord], destination: URL) throws {
        try XLSXExporter.exportSessionRecords(records: records.sorted(by: { $0.end > $1.end }), destination: destination)
    }

    private func exportRows(from start: Date, to end: Date) -> [UsageExportRow] {
        var rows: [UsageExportRow] = []
        for bucket in buckets where bucket.start >= start && bucket.start <= end {
            rows.append(UsageExportRow(start: bucket.start, scope: "total", appIdentifier: nil, networkName: bucket.networkDisplayName, download: bucket.download, upload: bucket.upload))
            for (identifier, pair) in bucket.apps.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
                rows.append(UsageExportRow(start: bucket.start, scope: "app", appIdentifier: identifier, networkName: bucket.networkDisplayName, download: pair.download, upload: pair.upload))
            }
        }
        return rows
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func continueDataForCurrentCycle() {
        let cycleStart = currentDataCycleStart().timeIntervalSince1970
        alertDefaults.set(cycleStart, forKey: "alerts.dataLimit.blockOverrideCycle")
        firewallController.setDataLimitInternetBlocked(false)
        objectWillChange.send()
    }

    // MARK: - Recording input

    private func consume(_ snapshot: NetworkSnapshot) {
        defer { previousSnapshot = snapshot }
        // Re-evaluate immediately on route/network changes so a target-network
        // block is released as soon as the user moves to an unrelated network.
        evaluateDataLimit()
        // Usage recording is the single source of persisted totals. Build 37 records
        // physical-interface identity with each slice so a data plan can follow one
        // Wi-Fi/hotspot connection without mixing in home/office Wi-Fi usage.
        let keepLongTermTotals = settings.recordingMode != .off &&
            (settings.resourceMode != .austerity || settings.austerityKeepTotalHistory)
        // Data Limit keeps only the minimum overall accounting it needs even when
        // Austerity pauses normal history. Core total measurement accuracy is never
        // reduced by a resource mode.
        // An explicitly started session also needs exact total accounting in
        // Austerity, even when ordinary long-term history is paused.
        guard keepLongTermTotals || settings.dataLimitEnabled || settings.sessionEnabled, let previousSnapshot else { return }

        // Build this map defensively. Interface snapshots come from the OS and
        // a duplicate name should overwrite the earlier sample, never trap the app.
        var previousInterfaces: [String: NetworkInterfaceCounterSnapshot] = [:]
        for counter in previousSnapshot.interfaceCounters {
            previousInterfaces[counter.interfaceName] = counter
        }
        var wroteDetailedSlice = false
        if !snapshot.interfaceCounters.isEmpty, !previousInterfaces.isEmpty {
            for current in snapshot.interfaceCounters {
                guard let previous = previousInterfaces[current.interfaceName] else { continue }
                let rx = current.receivedBytes >= previous.receivedBytes ? current.receivedBytes - previous.receivedBytes : 0
                let tx = current.sentBytes >= previous.sentBytes ? current.sentBytes - previous.sentBytes : 0
                guard rx > 0 || tx > 0 else { continue }
                wroteDetailedSlice = true
                add(download: rx,
                    upload: tx,
                    apps: [:],
                    networkIdentifier: current.networkIdentifier,
                    networkDisplayName: current.networkDisplayName,
                    networkIdentityReliable: current.identityReliable)
            }
        }

        // Migration/fallback: a snapshot created by Build 36 has no per-interface
        // detail. Record its aggregate delta against the current primary identity.
        guard !wroteDetailedSlice else { return }
        let rx = snapshot.totalReceivedBytes >= previousSnapshot.totalReceivedBytes ? snapshot.totalReceivedBytes - previousSnapshot.totalReceivedBytes : 0
        let tx = snapshot.totalSentBytes >= previousSnapshot.totalSentBytes ? snapshot.totalSentBytes - previousSnapshot.totalSentBytes : 0
        guard rx > 0 || tx > 0 else { return }
        add(download: rx,
            upload: tx,
            apps: [:],
            networkIdentifier: snapshot.networkIdentifier.isEmpty ? nil : snapshot.networkIdentifier,
            networkDisplayName: snapshot.networkDisplayName.isEmpty ? nil : snapshot.networkDisplayName,
            networkIdentityReliable: snapshot.networkIdentityReliable)
    }

    private func consumeAppUsages(_ usages: [AppNetworkUsage]) {
        let persistPerApp = settings.recordingMode == .perApp && settings.resourceMode != .austerity
        let classifyForAusterityLimit = settings.resourceMode == .austerity &&
            settings.dataLimitEnabled && settings.effectiveDataLimitTrafficScope == .internetOnly
        guard (persistPerApp || classifyForAusterityLimit), !usages.isEmpty else { return }

        // The live engine measures source processes. Build normal app history from
        // per-process deltas and then aggregate those deltas by stable app identity.
        // This avoids a helper appearing/disappearing from making an app's cumulative
        // total look as if it went backwards. Optional detailed history keeps the
        // same process deltas, but starts from a separate baseline when enabled.
        var currentProcessTotals: [String: AppBytePair] = [:]
        var processMetadata: [String: (String, String?)] = [:]

        for usage in usages {
            currentProcessTotals[usage.id] = AppBytePair(download: usage.cumulativeDownloadBytes,
                                                         upload: usage.cumulativeUploadBytes,
                                                         localDownload: usage.cumulativeLocalDownloadBytes,
                                                         localUpload: usage.cumulativeLocalUploadBytes,
                                                         unknownDownload: usage.cumulativeUnknownDownloadBytes,
                                                         unknownUpload: usage.cumulativeUnknownUploadBytes)
            processMetadata[usage.id] = (usage.displayName, usage.bundleIdentifier)
        }

        var appDeltas: [String: AppBytePair] = [:]
        for (processID, current) in currentProcessTotals {
            guard let previous = previousProcessTotals[processID],
                  current.download >= previous.download,
                  current.upload >= previous.upload else { continue }

            let delta = AppBytePair(download: current.download - previous.download,
                                    upload: current.upload - previous.upload,
                                    localDownload: current.localDownload >= previous.localDownload ? current.localDownload - previous.localDownload : 0,
                                    localUpload: current.localUpload >= previous.localUpload ? current.localUpload - previous.localUpload : 0,
                                    unknownDownload: current.unknownDownload >= previous.unknownDownload ? current.unknownDownload - previous.unknownDownload : 0,
                                    unknownUpload: current.unknownUpload >= previous.unknownUpload ? current.unknownUpload - previous.unknownUpload : 0)
            guard delta.download > 0 || delta.upload > 0 else { continue }

            let metadata = processMetadata[processID] ?? (processID, nil)
            let appKey = metadata.1 ?? processID
            var appDelta = appDeltas[appKey] ?? AppBytePair()
            appDelta.download &+= delta.download
            appDelta.upload &+= delta.upload
            appDelta.localDownload &+= delta.localDownload
            appDelta.localUpload &+= delta.localUpload
            appDelta.unknownDownload &+= delta.unknownDownload
            appDelta.unknownUpload &+= delta.unknownUpload
            appDeltas[appKey] = appDelta
        }

        var processDeltas: [String: ProcessUsageHistoryValue] = [:]
        if persistPerApp && settings.processDetailRecordingEnabled && settings.expertFeaturesEnabled && appTrafficMonitor.supportsProcessHierarchy {
            for (processID, current) in currentProcessTotals {
                guard let previous = previousDetailProcessTotals[processID],
                      current.download >= previous.download,
                      current.upload >= previous.upload else { continue }

                let delta = AppBytePair(download: current.download - previous.download,
                                        upload: current.upload - previous.upload,
                                        localDownload: current.localDownload >= previous.localDownload ? current.localDownload - previous.localDownload : 0,
                                        localUpload: current.localUpload >= previous.localUpload ? current.localUpload - previous.localUpload : 0,
                                        unknownDownload: current.unknownDownload >= previous.unknownDownload ? current.unknownDownload - previous.unknownDownload : 0,
                                        unknownUpload: current.unknownUpload >= previous.unknownUpload ? current.unknownUpload - previous.unknownUpload : 0)
                guard delta.download > 0 || delta.upload > 0 else { continue }

                let metadata = processMetadata[processID] ?? (processID, nil)
                processDeltas[processID] = ProcessUsageHistoryValue(displayName: metadata.0,
                                                                     bundleIdentifier: metadata.1,
                                                                     bytes: delta)
            }
        }

        previousProcessTotals = currentProcessTotals
        previousDetailProcessTotals = (persistPerApp && settings.processDetailRecordingEnabled && settings.expertFeaturesEnabled && appTrafficMonitor.supportsProcessHierarchy) ? currentProcessTotals : [:]
        guard !appDeltas.isEmpty || !processDeltas.isEmpty else { return }

        let snapshot = interfaceMonitor.snapshot
        if persistPerApp {
            add(download: 0,
                upload: 0,
                apps: appDeltas,
                processes: processDeltas,
                networkIdentifier: snapshot.networkIdentifier.isEmpty ? nil : snapshot.networkIdentifier,
                networkDisplayName: snapshot.networkDisplayName.isEmpty ? nil : snapshot.networkDisplayName,
                networkIdentityReliable: snapshot.networkIdentityReliable)
        } else if classifyForAusterityLimit {
            // Do not persist app/process identity in Austerity. Reduce exact source
            // counters immediately to anonymous Internet totals for the limit cycle.
            var internetDownload: UInt64 = 0
            var internetUpload: UInt64 = 0
            for pair in appDeltas.values {
                let excludedDownload = pair.localDownload &+ pair.unknownDownload
                let excludedUpload = pair.localUpload &+ pair.unknownUpload
                internetDownload &+= pair.download >= excludedDownload ? pair.download - excludedDownload : 0
                internetUpload &+= pair.upload >= excludedUpload ? pair.upload - excludedUpload : 0
            }
            add(download: 0,
                upload: 0,
                apps: [:],
                networkIdentifier: snapshot.networkIdentifier.isEmpty ? nil : snapshot.networkIdentifier,
                networkDisplayName: snapshot.networkDisplayName.isEmpty ? nil : snapshot.networkDisplayName,
                networkIdentityReliable: snapshot.networkIdentityReliable,
                classifiedInternetDownload: internetDownload,
                classifiedInternetUpload: internetUpload)
        }
    }

    private func add(download: UInt64,
                     upload: UInt64,
                     apps: [String: AppBytePair],
                     processes: [String: ProcessUsageHistoryValue] = [:],
                     networkIdentifier: String?,
                     networkDisplayName: String?,
                     networkIdentityReliable: Bool?,
                     classifiedInternetDownload: UInt64? = nil,
                     classifiedInternetUpload: UInt64? = nil) {
        let now = Date()
        archiveCompletedDataCycleIfNeeded(now: now)
        let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        if let index = buckets.lastIndex(where: {
            $0.start == minute && $0.networkIdentifier == networkIdentifier
        }) {
            buckets[index].download &+= download
            buckets[index].upload &+= upload
            if buckets[index].networkDisplayName == nil { buckets[index].networkDisplayName = networkDisplayName }
            if buckets[index].networkIdentityReliable != true { buckets[index].networkIdentityReliable = networkIdentityReliable }
            if let classifiedInternetDownload {
                buckets[index].classifiedInternetDownload = (buckets[index].classifiedInternetDownload ?? 0) &+ classifiedInternetDownload
            }
            if let classifiedInternetUpload {
                buckets[index].classifiedInternetUpload = (buckets[index].classifiedInternetUpload ?? 0) &+ classifiedInternetUpload
            }
            for (key, value) in apps {
                var pair = buckets[index].apps[key] ?? AppBytePair()
                pair.download &+= value.download
                pair.upload &+= value.upload
                pair.localDownload &+= value.localDownload
                pair.localUpload &+= value.localUpload
                pair.unknownDownload &+= value.unknownDownload
                pair.unknownUpload &+= value.unknownUpload
                buckets[index].apps[key] = pair
            }
            if !processes.isEmpty {
                var stored = buckets[index].processes ?? [:]
                for (key, value) in processes {
                    var existing = stored[key]?.bytes ?? AppBytePair()
                    existing.download &+= value.bytes.download
                    existing.upload &+= value.bytes.upload
                    existing.localDownload &+= value.bytes.localDownload
                    existing.localUpload &+= value.bytes.localUpload
                    existing.unknownDownload &+= value.bytes.unknownDownload
                    existing.unknownUpload &+= value.bytes.unknownUpload
                    stored[key] = ProcessUsageHistoryValue(displayName: value.displayName,
                                                           bundleIdentifier: value.bundleIdentifier,
                                                           bytes: existing)
                }
                buckets[index].processes = stored
            }
        } else {
            buckets.append(UsageBucket(start: minute,
                                       download: download,
                                       upload: upload,
                                       apps: apps,
                                       processes: processes.isEmpty ? nil : processes,
                                       networkIdentifier: networkIdentifier,
                                       networkDisplayName: networkDisplayName,
                                       networkIdentityReliable: networkIdentityReliable,
                                       classifiedInternetDownload: classifiedInternetDownload,
                                       classifiedInternetUpload: classifiedInternetUpload))
        }
        appPeriodCache.removeAll(keepingCapacity: true)
        totalPeriodCache.removeAll(keepingCapacity: true)
        evaluateDataLimit()
        if now.timeIntervalSince(lastPersist) >= 60 { trimAndPersist(force: true) }
    }

    // MARK: - Data limit

    private func initialDataLimitEnd() -> Date {
        let start = settings.dataLimitStartDate
        switch settings.dataLimitPeriodMode {
        case .endDate:
            return settings.dataLimitEndDate > start ? settings.dataLimitEndDate : start.addingTimeInterval(86400)
        case .selectedMonthEnd:
            let startMonth = calendar.component(.month, from: start)
            let selectedMonth = min(12, max(1, settings.dataLimitSelectedEndMonth))
            var year = calendar.component(.year, from: start)
            if selectedMonth < startMonth { year += 1 }
            var components: DateComponents
            if selectedMonth == 12 {
                components = DateComponents(year: year + 1, month: 1, day: 1, hour: 0, minute: 0, second: 0)
            } else {
                components = DateComponents(year: year, month: selectedMonth + 1, day: 1, hour: 0, minute: 0, second: 0)
            }
            let nextMonthStart = calendar.date(from: components) ?? start.addingTimeInterval(86400)
            return nextMonthStart.addingTimeInterval(-1)
        case .duration:
            let value = max(1, settings.dataLimitPeriodValue)
            switch settings.dataLimitPeriodUnit {
            case .days:
                return calendar.date(byAdding: .day, value: value, to: start) ?? start.addingTimeInterval(TimeInterval(value) * 86400)
            case .months:
                return calendar.date(byAdding: .month, value: value, to: start) ?? start.addingTimeInterval(TimeInterval(value) * 30 * 86400)
            }
        }
    }

    private func monthlyBoundary(after date: Date, day rawDay: Int) -> Date {
        let day = min(31, max(1, rawDay))
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        guard let year = dateComponents.year, let month = dateComponents.month else {
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86400)
        }
        for offset in 0...2 {
            guard let monthAnchor = calendar.date(byAdding: .month, value: offset, to: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date),
                  let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { continue }
            let range = calendar.range(of: .day, in: .month, for: monthAnchor)
            let validDay = min(day, range?.count ?? 28)
            let comps = calendar.dateComponents([.year, .month], from: monthAnchor)
            if let candidate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: validDay, hour: 0, minute: 0, second: 0)), candidate > date {
                return candidate
            }
            _ = interval
        }
        return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86400)
    }

    private func scopedTotal(from start: Date, to end: Date) -> AppBytePair {
        let selectedNetworkID: String? = settings.dataLimitNetworkTargetMode == .selectedNetwork
            ? settings.dataLimitNetworkIdentifier
            : nil
        var result = AppBytePair()

        for bucket in buckets where bucket.start >= start && bucket.start <= end {
            if let selectedNetworkID, bucket.networkIdentifier != selectedNetworkID { continue }

            if settings.effectiveDataLimitTrafficScope == .internetOnly,
               let classifiedDownload = bucket.classifiedInternetDownload,
               let classifiedUpload = bucket.classifiedInternetUpload {
                result.download &+= classifiedDownload
                result.upload &+= classifiedUpload
            } else if settings.effectiveDataLimitTrafficScope == .internetOnly,
                      settings.recordingMode == .perApp,
                      !bucket.apps.isEmpty {
                // Network Extension knows Internet/local classification per app.
                // The physical interface is attached to the minute slice here. If
                // no per-app sample exists for a slice, fall back to its interface
                // bytes rather than silently losing that traffic.
                var classified = AppBytePair()
                for pair in bucket.apps.values {
                    let excludedDownload = pair.localDownload &+ pair.unknownDownload
                    let excludedUpload = pair.localUpload &+ pair.unknownUpload
                    classified.download &+= pair.download >= excludedDownload ? pair.download - excludedDownload : 0
                    classified.upload &+= pair.upload >= excludedUpload ? pair.upload - excludedUpload : 0
                }
                result.download &+= classified.download
                result.upload &+= classified.upload
            } else {
                result.download &+= bucket.download
                result.upload &+= bucket.upload
            }
        }
        return result
    }

    private func evaluateDataLimit() {
        guard settings.dataLimitEnabled, settings.recordingMode != .off else {
            firewallController.setDataLimitInternetBlocked(false)
            return
        }

        // A per-network data plan must never block unrelated home/office Wi-Fi.
        // The filter itself is intentionally global, so the host enables the block
        // only while the configured target network is the active primary route.
        if settings.dataLimitNetworkTargetMode == .selectedNetwork {
            let activeID = interfaceMonitor.snapshot.networkIdentifier
            guard !settings.dataLimitNetworkIdentifier.isEmpty, activeID == settings.dataLimitNetworkIdentifier else {
                firewallController.setDataLimitInternetBlocked(false)
                return
            }
        }

        let limit = settings.dataLimitBytes
        guard limit > 0 else { return }

        let now = Date()
        let bounds = currentDataCycleBounds(at: now)
        guard now >= bounds.start else {
            firewallController.setDataLimitInternetBlocked(false)
            return
        }
        if settings.dataLimitEndBehavior == .stop && now >= bounds.end {
            firewallController.setDataLimitInternetBlocked(false)
            return
        }

        let usedPair = currentCycleTotal
        let used = usedPair.download &+ usedPair.upload
        let cycleStart = bounds.start.timeIntervalSince1970
        let reachedKey = "alerts.dataLimit.reachedCycle"
        let overrideKey = "alerts.dataLimit.blockOverrideCycle"

        if used >= limit {
            if alertDefaults.double(forKey: reachedKey) != cycleStart {
                let bodyKey = settings.dataLimitReachedAction == .blockInternet ? "dataLimitReachedBlockedBody" : "dataLimitReachedBody"
                postDataLimitNotification(titleKey: "dataLimitReachedTitle", body: L10n.text(bodyKey, language: settings.language))
                alertDefaults.set(cycleStart, forKey: reachedKey)
            }

            if settings.dataLimitReachedAction == .blockInternet,
               alertDefaults.double(forKey: overrideKey) != cycleStart {
                firewallController.setDataLimitInternetBlocked(true)
            } else if settings.dataLimitReachedAction == .continueData {
                firewallController.setDataLimitInternetBlocked(false)
            }
            return
        }

        if firewallController.isDataLimitInternetBlocked {
            firewallController.setDataLimitInternetBlocked(false)
        }

        guard settings.dataLimitWarningEnabled, !settings.dataLimitWarningRules.isEmpty else { return }
        let triggered = settings.dataLimitWarningRules
            .map { rule in (rule: rule, threshold: warningThresholdUsedBytes(rule, limit: limit)) }
            .filter { used >= $0.threshold }
            .sorted { $0.threshold < $1.threshold }
        guard let highest = triggered.last else { return }

        let highestCycleKey = "alerts.dataLimit.rule.\(highest.rule.id.uuidString).cycle"
        let highestTimeKey = "alerts.dataLimit.rule.\(highest.rule.id.uuidString).time"
        let alreadyInCycle = alertDefaults.double(forKey: highestCycleKey) == cycleStart
        let lastTime = alertDefaults.double(forKey: highestTimeKey)
        let repeatSeconds = TimeInterval(max(0, settings.dataLimitWarningRepeatMinutes) * 60)
        let repeatDue = alreadyInCycle && repeatSeconds > 0 && Date().timeIntervalSince1970 - lastTime >= repeatSeconds

        if !alreadyInCycle || repeatDue {
            let remaining = limit > used ? limit - used : 0
            let body: String
            switch highest.rule.mode {
            case .percentage:
                body = String(format: L10n.text("dataLimitWarningPercentBody", language: settings.language), Int(highest.rule.percentage.rounded()), SpeedFormatter.bytes(remaining))
            case .remainingAmount:
                body = String(format: L10n.text("dataLimitWarningRemainingBody", language: settings.language), SpeedFormatter.bytes(remaining))
            }
            postDataLimitNotification(titleKey: "dataLimitWarningTitle", body: body)
        }

        // Mark every lower threshold that is already behind us. If the Mac slept
        // through several thresholds, only the highest newly reached warning appears.
        let timestamp = Date().timeIntervalSince1970
        for item in triggered {
            let cycleKey = "alerts.dataLimit.rule.\(item.rule.id.uuidString).cycle"
            let timeKey = "alerts.dataLimit.rule.\(item.rule.id.uuidString).time"
            alertDefaults.set(cycleStart, forKey: cycleKey)
            if item.rule.id == highest.rule.id || alertDefaults.double(forKey: timeKey) == 0 {
                alertDefaults.set(timestamp, forKey: timeKey)
            }
        }
    }

    private func warningThresholdUsedBytes(_ rule: DataLimitWarningRule, limit: UInt64) -> UInt64 {
        switch rule.mode {
        case .percentage:
            return UInt64(Double(limit) * min(99, max(1, rule.percentage)) / 100.0)
        case .remainingAmount:
            return limit > rule.remainingBytes ? limit - rule.remainingBytes : 0
        }
    }

    private func postDataLimitNotification(titleKey: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text(titleKey, language: settings.language)
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func archiveCompletedDataCycleIfNeeded(now: Date) {
        guard settings.dataLimitEnabled else { return }
        let bounds = currentDataCycleBounds(at: now)
        let markerKey = "data.records.currentCycleStartV2"
        let limitKey = "data.records.currentCycleLimitV2"
        let signatureKey = "data.records.configSignatureV2"
        let signature = dataLimitConfigurationSignature
        let storedSignature = alertDefaults.string(forKey: signatureKey)

        // Editing the configured period is not the same as naturally finishing a
        // cycle. Reset the marker instead of generating a chain of fake records
        // while the user adjusts start/end/duration controls.
        if storedSignature != signature {
            alertDefaults.set(signature, forKey: signatureKey)
            alertDefaults.set(bounds.start.timeIntervalSince1970, forKey: markerKey)
            alertDefaults.set(Double(settings.dataLimitBytes), forKey: limitKey)
            firewallController.setDataLimitInternetBlocked(false)
            return
        }

        let previousTimestamp = alertDefaults.double(forKey: markerKey)
        if previousTimestamp == 0 {
            alertDefaults.set(bounds.start.timeIntervalSince1970, forKey: markerKey)
            alertDefaults.set(Double(settings.dataLimitBytes), forKey: limitKey)
            return
        }

        let previous = Date(timeIntervalSince1970: previousTimestamp)
        if bounds.start > previous.addingTimeInterval(0.5) {
            archiveDataCycle(start: previous, end: bounds.start.addingTimeInterval(-0.001), archivedLimit: UInt64(max(0, alertDefaults.double(forKey: limitKey))))
            // A manually applied starting remaining amount belongs only to its
            // current cycle. A naturally repeated/monthly cycle starts at the
            // full configured limit until the user applies a new value.
            if bounds.start > settings.dataLimitStartDate.addingTimeInterval(0.5) {
                settings.dataLimitStartingRemainingApplied = false
            }
            alertDefaults.set(bounds.start.timeIntervalSince1970, forKey: markerKey)
            alertDefaults.set(Double(settings.dataLimitBytes), forKey: limitKey)
            firewallController.setDataLimitInternetBlocked(false)
            return
        }

        if settings.dataLimitEndBehavior == .stop, now >= bounds.end, sameInstant(previous, bounds.start) {
            archiveDataCycle(start: bounds.start, end: bounds.end.addingTimeInterval(-0.001), archivedLimit: UInt64(max(0, alertDefaults.double(forKey: limitKey))))
            alertDefaults.set(bounds.end.timeIntervalSince1970, forKey: markerKey)
            firewallController.setDataLimitInternetBlocked(false)
        }
    }

    private var dataLimitConfigurationSignature: String {
        [
            String(format: "%.3f", settings.dataLimitStartDate.timeIntervalSince1970),
            settings.dataLimitPeriodMode.rawValue,
            "\(settings.dataLimitPeriodValue)",
            settings.dataLimitPeriodUnit.rawValue,
            String(format: "%.3f", settings.dataLimitEndDate.timeIntervalSince1970),
            settings.dataLimitEndBehavior.rawValue,
            settings.dataLimitNetworkTargetMode.rawValue,
            settings.dataLimitNetworkIdentifier
        ].joined(separator: "|")
    }

    private func archiveDataCycle(start: Date, end: Date, archivedLimit: UInt64) {
        let pair = scopedTotal(from: start, to: end)
        if pair.download > 0 || pair.upload > 0 {
            dataUsageRecords.append(DataUsageRecord(
                start: start,
                end: end,
                download: pair.download,
                upload: pair.upload,
                limitBytes: archivedLimit > 0 ? archivedLimit : settings.dataLimitBytes,
                networkIdentifier: settings.dataLimitNetworkTargetMode == .selectedNetwork ? settings.dataLimitNetworkIdentifier : nil,
                networkDisplayName: settings.dataLimitNetworkTargetMode == .selectedNetwork ? settings.dataLimitNetworkDisplayName : nil
            ))
            persistDataUsageRecords()
        }
    }

    // MARK: - Retention and persistence

    private func trimAndPersist(force: Bool) {
        var cutoff: Date
        if settings.historyRetentionDays == 0 {
            cutoff = .distantPast
        } else {
            let days = max(1, settings.historyRetentionDays)
            cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date.distantPast
        }
        if settings.dataLimitEnabled { cutoff = min(cutoff, currentDataCycleStart()) }
        if settings.sessionEnabled { cutoff = min(cutoff, settings.sessionStartDate) }
        buckets.removeAll { $0.start < cutoff }
        if force { persist() }
    }


    private func processTotals(for segments: [UsageSessionSegment], now: Date) -> [String: ProcessUsageHistoryValue] {
        var result: [String: ProcessUsageHistoryValue] = [:]
        var seenSlices = Set<String>()
        for segment in segments {
            let end = segment.end ?? now
            for bucket in buckets where bucket.start >= segment.start && bucket.start <= end {
                let sliceKey = "\(bucket.start.timeIntervalSince1970)|\(bucket.networkIdentifier ?? "legacy")"
                guard seenSlices.insert(sliceKey).inserted, let processes = bucket.processes else { continue }
                for (identifier, value) in processes {
                    var pair = result[identifier]?.bytes ?? AppBytePair()
                    pair.download &+= value.bytes.download
                    pair.upload &+= value.bytes.upload
                    pair.localDownload &+= value.bytes.localDownload
                    pair.localUpload &+= value.bytes.localUpload
                    pair.unknownDownload &+= value.bytes.unknownDownload
                    pair.unknownUpload &+= value.bytes.unknownUpload
                    result[identifier] = ProcessUsageHistoryValue(displayName: value.displayName, bundleIdentifier: value.bundleIdentifier, bytes: pair)
                }
            }
        }
        return result
    }

    private func appTotals(for segments: [UsageSessionSegment], now: Date) -> [String: AppBytePair] {
        var result: [String: AppBytePair] = [:]
        var seenSlices = Set<String>()
        for segment in segments {
            let end = segment.end ?? now
            for bucket in buckets where bucket.start >= segment.start && bucket.start <= end {
                let sliceKey = "\(bucket.start.timeIntervalSince1970)|\(bucket.networkIdentifier ?? "legacy")"
                guard seenSlices.insert(sliceKey).inserted else { continue }
                for (identifier, value) in bucket.apps {
                    var pair = result[identifier] ?? AppBytePair()
                    pair.download &+= value.download
                    pair.upload &+= value.upload
                    pair.localDownload &+= value.localDownload
                    pair.localUpload &+= value.localUpload
                    pair.unknownDownload &+= value.unknownDownload
                    pair.unknownUpload &+= value.unknownUpload
                    result[identifier] = pair
                }
            }
        }
        return result
    }

    private func total(for segments: [UsageSessionSegment], now: Date) -> AppBytePair {
        var result = AppBytePair()
        var seenSlices = Set<String>()
        for segment in segments {
            let end = segment.end ?? now
            for bucket in buckets where bucket.start >= segment.start && bucket.start <= end {
                // Build 37 may have several physical-network slices in one minute.
                // De-duplicate only the same minute+network slice across pause/resume.
                let sliceKey = "\(bucket.start.timeIntervalSince1970)|\(bucket.networkIdentifier ?? "legacy")"
                guard seenSlices.insert(sliceKey).inserted else { continue }
                result.download &+= bucket.download
                result.upload &+= bucket.upload
            }
        }
        return result
    }

    private func sameInstant(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private var dataUsageRecordsURL: URL? {
        applicationSupportFolder?.appendingPathComponent("data-usage-records.json")
    }

    private func persistDataUsageRecords() {
        guard let url = dataUsageRecordsURL, let data = try? JSONEncoder().encode(dataUsageRecords) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private struct SessionArchive: Codable {
        var records: [UsageSessionRecord]
        var active: ActiveUsageSessionState?
    }

    private var sessionsURL: URL? {
        applicationSupportFolder?.appendingPathComponent("usage-sessions.json")
    }

    private func persistSessions() {
        guard let url = sessionsURL else { return }
        let archive = SessionArchive(records: sessionRecords, active: activeSessionState)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private var fileURL: URL? {
        applicationSupportFolder?.appendingPathComponent("usage-history.json")
    }

    private var applicationSupportFolder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("NeManeem", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func persist() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(buckets) else { return }
        try? data.write(to: url, options: .atomic)
        lastPersist = Date()
        updateFileSize(url)
    }

    private func updateFileSize(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        storedFileSize = UInt64(values?.fileSize ?? 0)
    }
}
