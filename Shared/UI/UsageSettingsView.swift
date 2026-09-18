import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum StatisticsRange: String, CaseIterable, Identifiable {
    case today
    case last7
    case last30
    case all
    case month
    case custom
    var id: String { rawValue }
}

enum UsageExportFormat: String, CaseIterable, Identifiable {
    case xlsx, csv
    var id: String { rawValue }
}

private struct HistoricalAppUsageRow: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let totalBytes: UInt64
    let identityUsage: AppNetworkUsage?
}

private struct HistoricalProcessUsageRow: Identifiable {
    let id: String
    let name: String
    let totalBytes: UInt64
    let identityUsage: AppNetworkUsage?
}

struct UsageSettingsView: View {
    let highlight: String?
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var traffic = AppEnvironment.shared.appTrafficMonitor
    @State private var range: StatisticsRange = .today
    @State private var selectedMonth = Date()
    @State private var customRangeStart = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var customRangeEnd = Date()
    @State private var showingClear = false
    @State private var sessionName = ""
    @State private var showingSessionSchedule = false
    @State private var showingSessionEndSchedule = false
    @State private var showingClearSessionsConfirm = false
    @State private var expandedHistoryAppIDs: Set<String> = []
    @State private var historicalSystemServicesExpanded = false

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }
    private var calendar: Calendar { Calendar.current }
    private var dateDisplayLocale: Locale {
        L10n.locale(for: settings.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // MARK: Recording and saved usage data
                Section {
                    Toggle(t("usageRecording"), isOn: recordingEnabledBinding)

                    if settings.recordingMode == .perApp && settings.expertFeaturesEnabled {
                        SettingsItemWithHelp(settings.resourceMode == .austerity ? t("expertSuspendedInAusterity") : t("processDetailRecordingHelp") + (settings.processDetailRecordingEnabled && !traffic.supportsProcessHierarchy ? " " + t("processDetailExtensionPending") : "")) {
                            Toggle(t("processDetailRecording"), isOn: $settings.processDetailRecordingEnabled)
                                .disabled(settings.resourceMode == .austerity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        RetentionPeriodEditor(title: t("retention"), days: $settings.historyRetentionDays, t: t)
                            .disabled(settings.recordingMode == .off)
                        SettingsHelpText(t("retentionHelp"), level: .detail)
                        if settings.historyRetentionDays == 0 {
                            SettingsHelpText(t("retentionUnlimitedHelp"))
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(t("usageDataManagement"))
                            .font(.callout.weight(.semibold))
                        SettingsHelpText(t("usageHistoryManagementHelp"))
                        SettingsHelpText(t("usageSummaryExportHelp"), level: .detail)
                    }

                    if recorder.buckets.isEmpty {
                        SettingsHelpText(t("noUsageHistory"))
                    } else {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("storedHistory"))
                                Text(storedHistorySummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 8)
                            Menu {
                                Button("\(t("exportRecords")) · \(t("excelFormat"))") {
                                    exportUsage(format: .xlsx, includeSummary: false)
                                }
                                Button("\(t("exportRecords")) · \(t("csvFormat"))") {
                                    exportUsage(format: .csv, includeSummary: false)
                                }
                                Divider()
                                Button("\(t("exportWithSummary")) · \(t("excelFormat"))") {
                                    exportUsage(format: .xlsx, includeSummary: true)
                                }
                                Button("\(t("exportWithSummary")) · \(t("csvBundleFormat"))") {
                                    exportUsage(format: .csv, includeSummary: true)
                                }
                                Divider()
                                Button(t("deleteAllHistory"), role: .destructive) { showingClear = true }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .help(t("usageDataManagement"))
                        }
                    }
                } header: {
                    SettingsSectionHeader(t("historyData"), help: t("recordingLocalOnlyHelp"), detailHelp: t("usageRecordingHelp"))
                }
                .modifier(SettingsHighlightBackground(active: highlight == "recording" || highlight == "data"))

                // MARK: Session recording and session data management
                Section {
                    if settings.recordingMode == .off {
                        SettingsHelpText(t("sessionNeedsRecording"))
                    }

                    Toggle(t("showInPopover"), isOn: $settings.showSessionInPopover)

                    if settings.sessionEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t(recorder.sessionPaused ? "sessionPaused" : "sessionMeasuring"))
                                    .fontWeight(.semibold)
                                Text(sessionStartText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(SpeedFormatter.bytes(recorder.sessionTotal.download + recorder.sessionTotal.upload))
                                    .font(.headline)
                                    .monospacedDigit()
                                Text(durationText(recorder.sessionElapsed))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        TextField(t("sessionNameOptional"), text: $sessionName)

                        HStack(spacing: 8) {
                            Button(t("measurementStop")) {
                                _ = recorder.finishSession(name: sessionName)
                                sessionName = ""
                            }
                            .buttonStyle(NMNeutralActionButtonStyle())
                            Button(t(recorder.sessionPaused ? "measurementResume" : "measurementPause")) {
                                if recorder.sessionPaused { recorder.resumeSession() }
                                else { recorder.pauseSession() }
                            }
                            .buttonStyle(NMNeutralActionButtonStyle())
                            Button(t("scheduleMeasurementEnd")) {
                                showingSessionEndSchedule = true
                            }
                            .buttonStyle(NMNeutralActionButtonStyle())
                            Spacer()
                        }
                        if settings.sessionStartMode == .scheduled {
                            Text("\(t("scheduledEnd")) · \(scheduleDateText(settings.scheduledSessionEndDate))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if recorder.hasPendingSessionSchedule {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t("scheduledSession"))
                                .fontWeight(.semibold)
                            Text(pendingSessionScheduleText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button(t("cancelSchedule")) { recorder.cancelScheduledSession() }
                                    .buttonStyle(NMNeutralActionButtonStyle())
                                Spacer()
                            }
                        }
                    } else {
                        HStack {
                            Button(t("startSession")) {
                                sessionName = ""
                                _ = recorder.startSession()
                            }
                            .buttonStyle(NMNeutralActionButtonStyle())
                            .disabled(settings.recordingMode == .off)

                            Button(t("scheduleSession")) {
                                showingSessionSchedule = true
                            }
                            .buttonStyle(NMNeutralActionButtonStyle())
                            .disabled(settings.recordingMode == .off)

                            Spacer()
                            Text(t("sessionReady"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(t("sessionDataManagement"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if !displayedSessionRecords.isEmpty {
                                Menu {
                                    Button("\(t("exportAllRecords")) · \(t("excelFormat"))") {
                                        exportSessionRecords(format: .xlsx)
                                    }
                                    Button("\(t("exportAllRecords")) · \(t("csvFormat"))") {
                                        exportSessionRecords(format: .csv)
                                    }
                                    Divider()
                                    Button(t("clearSessionRecords"), role: .destructive) {
                                        showingClearSessionsConfirm = true
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                        SettingsHelpText(t("sessionRecordsHelp"))
                    }

                    if displayedSessionRecords.isEmpty {
                        SettingsHelpText(t("noSessionRecords"))
                    } else {
                        ForEach(displayedSessionRecords) { record in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sessionRecordTitle(record))
                                        .lineLimit(1)
                                    Text("\(dateRange(record.start, record.end)) · \(durationText(record.duration))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(SpeedFormatter.bytes(record.total))
                                    .monospacedDigit()
                                Menu {
                                    Button("\(t("exportSelectedRecord")) · \(t("excelFormat"))") {
                                        exportSessionRecord(record, format: .xlsx)
                                    }
                                    Button("\(t("exportSelectedRecord")) · \(t("csvFormat"))") {
                                        exportSessionRecord(record, format: .csv)
                                    }
                                    Divider()
                                    Button(t("deleteSessionRecord"), role: .destructive) {
                                        recorder.deleteSessionRecord(id: record.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .font(.callout)
                        }
                    }
                } header: {
                    SettingsSectionHeader(t("sessionRecording"), help: t("sessionStopwatchEssential"), detailHelp: t("sessionStopwatchDetail"))
                }
                .modifier(SettingsHighlightBackground(active: highlight == "session"))

                // MARK: App usage
                Section {
                    if settings.recordingMode == .off {
                        SettingsHelpText(t("recordingOffHelp"))
                    }

                    NMValueChoice(t("displayPeriod"), selection: $range, options: [
                        (.today, t("today")),
                        (.last7, t("days7")),
                        (.last30, t("days30")),
                        (.all, t("all")),
                        (.month, t("monthly")),
                        (.custom, t("custom"))
                    ])

                    if range == .month {
                        HStack {
                            Text(t("month"))
                            Spacer()
                            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(NMUtilityIconButtonStyle())
                                .disabled(!canMoveMonth(-1))
                            Text(monthTitle(selectedMonth))
                                .monospacedDigit()
                                .frame(minWidth: 116)
                                .multilineTextAlignment(.center)
                            Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(NMUtilityIconButtonStyle())
                                .disabled(!canMoveMonth(1))
                        }
                    } else if range == .custom {
                        HStack(spacing: 12) {
                            DatePicker(t("rangeStart"), selection: $customRangeStart, displayedComponents: [.date, .hourAndMinute])
                                .nmNeutralValueControl()
                                .environment(\.locale, dateDisplayLocale)
                            DatePicker(t("rangeEnd"), selection: $customRangeEnd, in: customRangeStart..., displayedComponents: [.date, .hourAndMinute])
                                .nmNeutralValueControl()
                                .environment(\.locale, dateDisplayLocale)
                        }
                    }

                    HStack {
                        Text(t("availableRange"))
                        Spacer()
                        Text(retentionDisplayText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    let total = usageTotal
                    HStack(spacing: 28) {
                        metricCard(t("download"), SpeedFormatter.bytes(total.download))
                        metricCard(t("upload"), SpeedFormatter.bytes(total.upload))
                        metricCard(t("totalLabel"), SpeedFormatter.bytes(total.download + total.upload))
                    }

                    if settings.recordingMode == .perApp && !historicalRows.isEmpty {
                        HStack(spacing: 10) {
                            Text(t("processName"))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text(t("usage"))
                                .font(.callout.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)

                        ForEach(historicalAppRows) { app in
                            historicalAppUsageRow(app)
                        }

                        if !historicalSystemRows.isEmpty {
                            Button {
                                historicalSystemServicesExpanded.toggle()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: historicalSystemServicesExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 12)
                                    Text("\(t("systemProcesses")) \(historicalSystemRows.count)")
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)

                            if historicalSystemServicesExpanded {
                                ForEach(historicalSystemRows) { app in
                                    historicalAppUsageRow(app)
                                }
                            }
                        }

                        if settings.processDetailRecordingEnabled && !recorder.hasProcessDetailHistory(from: rangeBounds.start, to: rangeBounds.end) {
                            SettingsHelpText(t("processDetailHistoryStartsAfterEnable"))
                        }
                    } else if settings.recordingMode == .perApp {
                        SettingsHelpText(t("noUsageHistory"))
                    }
                } header: {
                    SettingsSectionHeader(t("appUsageBreakdown"))
                }
                .modifier(SettingsHighlightBackground(active: highlight == "usage"))
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .confirmationDialog(t("clearConfirm"), isPresented: $showingClear) {
            Button(t("clear"), role: .destructive) { recorder.clearHistory() }
        }
        .confirmationDialog(t("clearSessionRecords"), isPresented: $showingClearSessionsConfirm, titleVisibility: .visible) {
            Button(t("clearSessionRecords"), role: .destructive) { recorder.clearSessionRecords() }
            Button(t("cancel"), role: .cancel) {}
        } message: {
            Text(t("clearSessionRecordsConfirm"))
        }
        .sheet(isPresented: $showingSessionSchedule) {
            SessionScheduleSheet()
        }
        .sheet(isPresented: $showingSessionEndSchedule) {
            SessionEndScheduleSheet()
        }
        .onAppear {
            normalizeRetention()
            customRangeStart = max(retentionStart, calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            customRangeEnd = Date()
            traffic.hydrateObservedCatalogAfterLaunch()
        }
        .onChange(of: settings.historyRetentionDays) { _ in
            clampSelectedMonth()
            if customRangeStart < retentionStart { customRangeStart = retentionStart }
        }
    }


    private var recordingEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.recordingMode != .off },
            set: { enabled in settings.recordingMode = enabled ? .perApp : .off }
        )
    }

    private var earliestRecordedDate: Date {
        return recorder.buckets.map(\.start).min() ?? calendar.startOfDay(for: Date())
    }

    private var retentionStart: Date {
        guard settings.historyRetentionDays > 0 else {
            return calendar.startOfDay(for: earliestRecordedDate)
        }
        let days = max(1, settings.historyRetentionDays)
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
    }

    private var retentionDisplayText: String {
        settings.historyRetentionDays == 0 ? t("unlimited") : String(format: t("retentionDaysFormat"), settings.historyRetentionDays)
    }

    private var rangeBounds: (start: Date, end: Date) {
        let now = Date()
        switch range {
        case .today:
            return (max(calendar.startOfDay(for: now), retentionStart), now)
        case .last7:
            let raw = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            return (max(raw, retentionStart), now)
        case .last30:
            let raw = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
            return (max(raw, retentionStart), now)
        case .all:
            return (calendar.startOfDay(for: earliestRecordedDate), now)
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else { return (retentionStart, now) }
            let start = max(monthInterval.start, retentionStart)
            let end = min(now, monthInterval.end.addingTimeInterval(-1))
            return (start, max(start, end))
        case .custom:
            let start = max(customRangeStart, retentionStart)
            let end = min(max(customRangeEnd, start), now)
            return (start, end)
        }
    }

    private var historicalRows: [HistoricalAppUsageRow] {
        let totals = recorder.appTotals(from: rangeBounds.start, to: rangeBounds.end)
        let mapped = applyingManualParentMappings(traffic.observedUsages, mappings: settings.manualParentAppMappings)
        let groups = appUsageGroups(mapped)
        var identityByRecordedKey: [String: AppNetworkUsage] = [:]
        for group in groups {
            identityByRecordedKey[group.id] = group.usage
            for member in group.members {
                identityByRecordedKey[member.id] = group.usage
                if let bundleIdentifier = member.bundleIdentifier, identityByRecordedKey[bundleIdentifier] == nil {
                    identityByRecordedKey[bundleIdentifier] = group.usage
                }
            }
        }

        var bytesByPresentationID: [String: UInt64] = [:]
        var identityByPresentationID: [String: AppNetworkUsage] = [:]
        var fallbackNameByPresentationID: [String: String] = [:]
        for (recordedKey, pair) in totals {
            let identity = identityByRecordedKey[recordedKey]
            let presentationID = identity?.id ?? recordedKey
            bytesByPresentationID[presentationID, default: 0] &+= pair.download &+ pair.upload
            if let identity { identityByPresentationID[presentationID] = identity }
            fallbackNameByPresentationID[presentationID] = identity?.displayName ?? recordedKey
        }

        return bytesByPresentationID.map { key, bytes in
            let usage = identityByPresentationID[key]
            return HistoricalAppUsageRow(
                id: key,
                name: usage?.displayName ?? fallbackNameByPresentationID[key] ?? key,
                icon: usage?.icon ?? Self.historicalUsageFallbackIcon,
                totalBytes: bytes,
                identityUsage: usage
            )
        }
        .filter { $0.totalBytes > 0 }
        .sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    private var historicalAppRows: [HistoricalAppUsageRow] {
        historicalRows.filter { $0.identityUsage?.isSystemProcess != true }
    }

    private var historicalSystemRows: [HistoricalAppUsageRow] {
        historicalRows.filter { $0.identityUsage?.isSystemProcess == true }
    }

    private func historicalProcesses(for appIdentifier: String) -> [HistoricalProcessUsageRow] {
        let observedByProcess = Dictionary(traffic.observedUsages.compactMap { usage -> (String, AppNetworkUsage)? in
            guard let process = usage.processIdentifier, !process.isEmpty else { return nil }
            return (process, usage)
        }, uniquingKeysWith: { first, _ in first })
        return recorder.processTotals(from: rangeBounds.start, to: rangeBounds.end, appIdentifier: appIdentifier)
            .map { identifier, value in
                HistoricalProcessUsageRow(id: identifier,
                                          name: value.displayName,
                                          totalBytes: value.bytes.download &+ value.bytes.upload,
                                          identityUsage: observedByProcess[identifier])
            }
            .filter { $0.totalBytes > 0 }
            .sorted { lhs, rhs in
                if lhs.totalBytes == rhs.totalBytes { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.totalBytes > rhs.totalBytes
            }
    }

    private static let historicalUsageFallbackIcon: NSImage = {
        let source = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil)
            ?? NSWorkspace.shared.icon(for: .application)
        let icon = (source.copy() as? NSImage) ?? source
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }()

    private func historicalAppIdentity(_ app: HistoricalAppUsageRow) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Text(app.name)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func historicalAppUsageRow(_ app: HistoricalAppUsageRow) -> some View {
        let processRows = historicalProcesses(for: app.id)
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                if !processRows.isEmpty {
                    Button {
                        if expandedHistoryAppIDs.contains(app.id) { expandedHistoryAppIDs.remove(app.id) }
                        else { expandedHistoryAppIDs.insert(app.id) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: expandedHistoryAppIDs.contains(app.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            historicalAppIdentity(app)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    historicalAppIdentity(app)
                }
                Spacer(minLength: 8)
                Text(SpeedFormatter.bytes(app.totalBytes))
                    .monospacedDigit()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .if(app.identityUsage != nil) { view in
                view.contextMenu {
                    if let usage = app.identityUsage {
                        AppIdentityContextMenuContent(usage: usage, preferProcess: false)
                    }
                }
            }

            if expandedHistoryAppIDs.contains(app.id) {
                VStack(spacing: 0) {
                    ForEach(processRows) { row in
                        HStack(spacing: 8) {
                            Spacer().frame(width: 22)
                            Image(systemName: "gearshape.2")
                                .foregroundStyle(.secondary)
                            Text(row.name)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(SpeedFormatter.bytes(row.totalBytes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .if(row.identityUsage != nil) { view in
                            view.contextMenu {
                                if let usage = row.identityUsage {
                                    AppIdentityContextMenuContent(usage: usage, preferProcess: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var usageTotal: AppBytePair {
        return recorder.total(from: rangeBounds.start, to: rangeBounds.end)
    }

    private var displayedSessionRecords: [UsageSessionRecord] {
        return recorder.sessionRecords.sorted { $0.end > $1.end }
    }

    private func exportSessionRecords(format: UsageExportFormat) {
        let records = recorder.sessionRecords.sorted { $0.end > $1.end }
        guard !records.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = t("recentSessions")
        switch format {
        case .xlsx:
            panel.nameFieldStringValue = "NeManeem-session-records.xlsx"
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        case .csv:
            panel.nameFieldStringValue = "NeManeem-session-records.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .xlsx: try recorder.exportSessionRecordsXLSX(records, destination: url)
            case .csv: try recorder.exportSessionRecordsCSV(records, destination: url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = t("recentSessions")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func exportSessionRecord(_ record: UsageSessionRecord, format: UsageExportFormat) {
        let panel = NSSavePanel()
        panel.title = t("sessionDataManagement")
        let safeID = record.id.uuidString.lowercased()
        switch format {
        case .xlsx:
            panel.nameFieldStringValue = "NeManeem-session-\(safeID).xlsx"
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        case .csv:
            panel.nameFieldStringValue = "NeManeem-session-\(safeID).csv"
            panel.allowedContentTypes = [.commaSeparatedText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .xlsx: try recorder.exportSessionRecordsXLSX([record], destination: url)
            case .csv: try recorder.exportSessionRecordsCSV([record], destination: url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = t("sessionDataManagement")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func normalizeRetention() {
        if settings.historyRetentionDays < 0 { settings.historyRetentionDays = 30 }
        clampSelectedMonth()
    }

    private func clampSelectedMonth() {
        guard let currentStart = calendar.dateInterval(of: .month, for: Date())?.start else { return }
        if selectedMonth > currentStart { selectedMonth = currentStart }
        if let selectedInterval = calendar.dateInterval(of: .month, for: selectedMonth), selectedInterval.end < retentionStart {
            selectedMonth = retentionStart
        }
    }

    private func canMoveMonth(_ delta: Int) -> Bool {
        guard let candidate = calendar.date(byAdding: .month, value: delta, to: selectedMonth),
              let interval = calendar.dateInterval(of: .month, for: candidate),
              let current = calendar.dateInterval(of: .month, for: Date()) else { return false }
        if delta < 0 { return interval.end >= retentionStart }
        return interval.start <= current.start
    }

    private func moveMonth(_ delta: Int) {
        guard canMoveMonth(delta), let date = calendar.date(byAdding: .month, value: delta, to: selectedMonth) else { return }
        selectedMonth = date
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch settings.language {
        case .korean: formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "yyyy년 M월"
        case .japanese: formatter.locale = Locale(identifier: "ja_JP"); formatter.dateFormat = "yyyy年M月"
        case .spanish: formatter.locale = Locale(identifier: "es_ES"); formatter.dateFormat = "MMMM yyyy"
        case .english: formatter.locale = Locale(identifier: "en_US"); formatter.dateFormat = "MMMM yyyy"
        case .system: formatter.locale = dateDisplayLocale; formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        }
        return formatter.string(from: date)
    }

    private var pendingSessionScheduleText: String {
        let start = scheduleDateText(settings.scheduledSessionStartDate)
        let end = scheduleDateText(settings.scheduledSessionEndDate)
        return "\(start) → \(end)"
    }

    private func scheduleDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var sessionStartText: String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: settings.sessionStartDate)
    }

    private func sessionRecordTitle(_ record: UsageSessionRecord) -> String {
        if let name = record.name, !name.isEmpty { return name }
        return t("unnamedSession")
    }

    private func dateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private var storedHistorySummary: String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let first = recorder.buckets.map(\.start).min() ?? earliestRecordedDate
        let last = recorder.buckets.map(\.start).max() ?? first
        let rangeText = calendar.isDate(first, inSameDayAs: last)
            ? formatter.string(from: first)
            : "\(formatter.string(from: first)) – \(formatter.string(from: last))"
        return "\(rangeText) · \(SpeedFormatter.bytes(recorder.storedFileSize))"
    }

    private func exportUsage(format: UsageExportFormat, includeSummary: Bool) {
        let panel = NSSavePanel()
        switch (format, includeSummary) {
        case (.xlsx, false):
            panel.nameFieldStringValue = "NeManeem-usage.xlsx"
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        case (.xlsx, true):
            panel.nameFieldStringValue = "NeManeem-usage-with-summary.xlsx"
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        case (.csv, false):
            panel.nameFieldStringValue = "NeManeem-usage.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
        case (.csv, true):
            panel.nameFieldStringValue = "NeManeem-usage-with-summary.zip"
            panel.allowedContentTypes = [UTType(filenameExtension: "zip")!]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch (format, includeSummary) {
            case (.xlsx, let summary):
                try recorder.exportXLSX(from: rangeBounds.start, to: rangeBounds.end, intervalMinutes: 5, includeSummary: summary, destination: url)
            case (.csv, false):
                try recorder.exportCSV(from: rangeBounds.start, to: rangeBounds.end, intervalMinutes: 5, destination: url)
            case (.csv, true):
                try recorder.exportCSVWithSummaryBundle(from: rangeBounds.start, to: rangeBounds.end, intervalMinutes: 5, destination: url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = t("usageDataManagement")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

private struct SessionScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder

    @State private var startDate = Date().addingTimeInterval(300)
    @State private var endMode: SessionScheduleEndMode = .endDate
    @State private var endDate = Date().addingTimeInterval(3900)
    @State private var durationDays = 0
    @State private var durationHours = 1
    @State private var durationMinutes = 0

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("scheduleSession"))
                .font(.title3.weight(.semibold))

            Form {
                DatePicker(t("sessionStartTime"), selection: $startDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .nmNeutralValueControl()
                    .environment(\.locale, dateDisplayLocale)

                Picker(t("sessionEndMethod"), selection: $endMode) {
                    Text(t("endAtTime")).tag(SessionScheduleEndMode.endDate)
                    Text(t("measurementDuration")).tag(SessionScheduleEndMode.duration)
                }
                .pickerStyle(.segmented)
                .nmAccentValueControl()

                if endMode == .endDate {
                    DatePicker(t("sessionEndTime"), selection: $endDate, in: minimumEndDate..., displayedComponents: [.date, .hourAndMinute])
                        .nmNeutralValueControl()
                        .environment(\.locale, dateDisplayLocale)
                } else {
                    HStack(spacing: 7) {
                        Text(t("measurementDuration"))
                        Spacer(minLength: 12)
                        TextField("", value: $durationDays, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("days")).foregroundStyle(.secondary)
                        TextField("", value: $durationHours, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("hours")).foregroundStyle(.secondary)
                        TextField("", value: $durationMinutes, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("minutes")).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(t("calculatedEnd"))
                    Spacer()
                    Text(dateText(calculatedEnd))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .formStyle(.grouped)
        .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button(t("cancel")) { dismiss() }
                Button(t("schedule")) { saveSchedule() }
                    .buttonStyle(NMPrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!scheduleIsValid)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear(perform: loadStoredValues)
        .onChange(of: startDate) { _ in
            if endMode == .endDate && endDate < minimumEndDate { endDate = minimumEndDate }
        }
        .onChange(of: endMode) { mode in
            if mode == .endDate && endDate < minimumEndDate { endDate = minimumEndDate }
        }
        .onChange(of: durationDays) { value in durationDays = min(365, max(0, value)) }
        .onChange(of: durationHours) { value in durationHours = min(23, max(0, value)) }
        .onChange(of: durationMinutes) { value in durationMinutes = min(59, max(0, value)) }
    }

    private var minimumEndDate: Date { startDate.addingTimeInterval(60) }

    private var durationTotalMinutes: Int {
        max(1, durationDays * 1440 + durationHours * 60 + durationMinutes)
    }

    private var durationSeconds: TimeInterval {
        TimeInterval(durationTotalMinutes * 60)
    }

    private var calculatedEnd: Date {
        endMode == .endDate ? endDate : startDate.addingTimeInterval(durationSeconds)
    }

    private var scheduleIsValid: Bool {
        startDate > Date() && calculatedEnd >= minimumEndDate && (endMode == .endDate || durationDays > 0 || durationHours > 0 || durationMinutes > 0)
    }

    private func loadStoredValues() {
        let now = Date()
        startDate = max(settings.scheduledSessionStartDate, now.addingTimeInterval(300))
        endMode = settings.scheduledSessionEndMode
        let storedMinutes = max(1, settings.scheduledSessionDurationMinutes)
        durationDays = storedMinutes / 1440
        durationHours = (storedMinutes % 1440) / 60
        durationMinutes = storedMinutes % 60
        endDate = max(settings.scheduledSessionEndDate, startDate.addingTimeInterval(3600))
    }

    private func saveSchedule() {
        let totalMinutes = durationTotalMinutes
        settings.scheduledSessionEndMode = endMode
        settings.scheduledSessionDurationMinutes = totalMinutes
        settings.scheduledSessionEndDate = calculatedEnd
        recorder.scheduleSession(start: startDate, end: calculatedEnd)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        dismiss()
    }

    private var dateDisplayLocale: Locale {
        L10n.locale(for: settings.language)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SessionEndScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder

    @State private var endMode: SessionScheduleEndMode = .endDate
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var durationDays = 0
    @State private var durationHours = 1
    @State private var durationMinutes = 0

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("scheduleMeasurementEnd"))
                .font(.title3.weight(.semibold))

            Form {
                Picker(t("sessionEndMethod"), selection: $endMode) {
                    Text(t("endAtTime")).tag(SessionScheduleEndMode.endDate)
                    Text(t("measurementDuration")).tag(SessionScheduleEndMode.duration)
                }
                .pickerStyle(.segmented)
                .nmAccentValueControl()

                if endMode == .endDate {
                    DatePicker(t("sessionEndTime"), selection: $endDate, in: minimumEndDate..., displayedComponents: [.date, .hourAndMinute])
                        .nmNeutralValueControl()
                        .environment(\.locale, dateDisplayLocale)
                } else {
                    HStack(spacing: 7) {
                        Text(t("measurementDuration"))
                        Spacer(minLength: 12)
                        TextField("", value: $durationDays, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("days")).foregroundStyle(.secondary)
                        TextField("", value: $durationHours, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("hours")).foregroundStyle(.secondary)
                        TextField("", value: $durationMinutes, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("minutes")).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(t("calculatedEnd"))
                    Spacer()
                    Text(dateText(calculatedEnd))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button(t("cancel")) { dismiss() }
                Button(t("schedule")) { saveSchedule() }
                    .buttonStyle(NMPrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!scheduleIsValid)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear(perform: loadStoredValues)
        .onChange(of: durationDays) { value in durationDays = min(365, max(0, value)) }
        .onChange(of: durationHours) { value in durationHours = min(23, max(0, value)) }
        .onChange(of: durationMinutes) { value in durationMinutes = min(59, max(0, value)) }
    }

    private var minimumEndDate: Date { Date().addingTimeInterval(60) }
    private var rawDurationTotalMinutes: Int { durationDays * 1440 + durationHours * 60 + durationMinutes }
    private var durationTotalMinutes: Int { max(1, rawDurationTotalMinutes) }
    private var calculatedEnd: Date {
        endMode == .endDate ? endDate : Date().addingTimeInterval(TimeInterval(durationTotalMinutes * 60))
    }
    private var scheduleIsValid: Bool {
        if endMode == .duration { return rawDurationTotalMinutes > 0 }
        return calculatedEnd >= minimumEndDate
    }

    private func loadStoredValues() {
        let now = Date()
        endMode = settings.scheduledSessionEndMode
        let storedMinutes = max(1, settings.scheduledSessionDurationMinutes)
        durationDays = storedMinutes / 1440
        durationHours = (storedMinutes % 1440) / 60
        durationMinutes = storedMinutes % 60
        endDate = max(settings.scheduledSessionEndDate, now.addingTimeInterval(3600))
    }

    private func saveSchedule() {
        settings.scheduledSessionEndMode = endMode
        settings.scheduledSessionDurationMinutes = durationTotalMinutes
        settings.scheduledSessionEndDate = calculatedEnd
        recorder.scheduleActiveSessionEnd(at: calculatedEnd)
        dismiss()
    }

    private var dateDisplayLocale: Locale {
        L10n.locale(for: settings.language)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Settings 5. Data Limit

