import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MonitorWindowRootView: View {
    @ObservedObject private var environment = AppEnvironment.shared
    @ObservedObject private var settings = AppEnvironment.shared.settings
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        MonitorModeView()
            .tint(NeManeemTheme.accent)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button {
                            settings.alwaysOnTopMonitor.toggle()
                        } label: {
                            Image(systemName: settings.alwaysOnTopMonitor ? "pin.fill" : "pin")
                        }
                        .help(t(settings.alwaysOnTopMonitor ? "alwaysOnTopEnabled" : "alwaysOnTop"))
                        .accessibilityLabel(t("alwaysOnTop"))

                        Button {
                            environment.requestedPresentationScreenFrame = NSApp.keyWindow?.screen?.visibleFrame
                            environment.requestSettingsSection?("popover-monitor")
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help(t("monitorSettings"))
                        .accessibilityLabel(t("monitorSettings"))
                    }
                }
            }
    }
}

private enum ExpertTrafficFilter: String, CaseIterable, Identifiable {
    case all
    case internet
    case local
    case unknown
    var id: String { rawValue }
}

struct MonitorModeView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var interface = AppEnvironment.shared.interfaceMonitor
    @ObservedObject private var traffic = AppEnvironment.shared.appTrafficMonitor
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hiddenExpanded = false
    @State private var systemExpanded = false
    @State private var lowActivityExpanded = false
    @State private var unselectedExpanded = false
    @State private var localExpanded = false
    @State private var unknownExpanded = false
    @State private var expandedAppIDs: Set<String> = []
    @State private var draggingID: String?
    @State private var dropTargetID: String?
    @State private var displayedUsages: [AppNetworkUsage] = []
    @State private var rateBaseline: [String: AppUsageCounterBaseline] = [:]
    @State private var rateBaselineDate = Date()
    @State private var visibilityClock = Date()
    @State private var lowActivityTracker = LowActivityWindowTracker()
    @State private var stableUsageOrder: [String] = []
    @State private var expertSearchText = ""
    @State private var expertFilter: ExpertTrafficFilter = .all
    @State private var expertDetailUsage: AppNetworkUsage?
    @State private var selectedTrafficID: String?

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }
    private var scale: CGFloat { settings.effectiveMonitorScale.factor }
    private var displayColumns: [StatusColumn] { activeStatusColumns(settings.effectiveMonitorColumns, appBlockingEnabled: firewall.isEnabled) }

    var body: some View {
        VStack(spacing: 0) {
            if settings.effectiveMonitorShowTotalSpeed {
                TrafficSummaryRow(title: t("overall"),
                                  download: interface.snapshot.downloadBytesPerSecond,
                                  upload: interface.snapshot.uploadBytesPerSecond,
                                  processMode: settings.effectiveMonitorProcessDisplay,
                                  unitMode: settings.effectiveMonitorUnitMode,
                                  directionDisplay: settings.effectiveMonitorDirectionDisplay,
                                  scale: scale,
                                  columns: displayColumns,
                                  expandProcessColumn: true)
                Divider()
            }

            if expertFeaturesActive {
                expertToolbar
                Divider()
            }

            VStack(spacing: 0) {
                TrafficTableHeader(processMode: settings.effectiveMonitorProcessDisplay,
                                   unitMode: settings.effectiveMonitorUnitMode,
                                   directionDisplay: settings.effectiveMonitorDirectionDisplay,
                                   scale: scale,
                                   columns: displayColumns,
                                   expandProcessColumn: true)
                Divider()

                if let message = stateMessage {
                    VStack(spacing: 8) {
                        if !traffic.hasCompletedInitialSample && traffic.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(message)
                            .font(.system(size: 13 * scale))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if traffic.connectionFailureCount >= 3 {
                            VStack(spacing: 7) {
                                Text(t("networkSettingsPossibleProblem"))
                                    .font(.system(size: 11.5 * scale))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(t("troubleshootShortcut")) {
                                    AppEnvironment.shared.requestSettingsSection?("troubleshooting")
                                }
                                .buttonStyle(NMNeutralActionButtonStyle())
                                .controlSize(.small)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 14)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(normalAppGroups) { group in
                                monitorAppGroupRows(group, allowManualDrag: settings.effectiveMonitorSortMode == .manual)
                                Divider().padding(.leading, dividerInset)
                            }

                            ForEach(sortedTrafficUsages(ungroupedSystemUsages, by: settings.effectiveMonitorSortMode, manualOrder: settings.effectiveMonitorManualOrder)) { usage in
                                monitorTrafficRow(usage, indented: false, allowManualDrag: settings.effectiveMonitorSortMode == .manual)
                                Divider().padding(.leading, dividerInset)
                            }

                            if !systemUsages.isEmpty {
                                TrafficGroupRow(title: t("systemServices"), count: systemUsages.count, usages: systemUsages, isExpanded: $systemExpanded, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope, expandProcessColumn: true)
                                Divider().padding(.leading, dividerInset)
                                if systemExpanded {
                                    ForEach(sortedTrafficUsages(systemUsages, by: .name, manualOrder: [])) { usage in
                                        monitorTrafficRow(usage, indented: true, allowManualDrag: false)
                                        Divider().padding(.leading, dividerInset + 14)
                                    }
                                }
                            }

                            if !lowActivityAppGroups.isEmpty {
                                let usages = lowActivityAppGroups.map(\.usage)
                                TrafficGroupRow(title: t("lowActivityApps"), count: usages.count, usages: usages, isExpanded: $lowActivityExpanded, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope, expandProcessColumn: true)
                                Divider().padding(.leading, dividerInset)
                                if lowActivityExpanded {
                                    ForEach(lowActivityAppGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                        monitorAppGroupRows(group, allowManualDrag: false)
                                        Divider().padding(.leading, dividerInset + 14)
                                    }
                                }
                            }

                            if !unselectedAppGroups.isEmpty {
                                let usages = unselectedAppGroups.map(\.usage)
                                TrafficGroupRow(title: t("otherApps"), count: usages.count, usages: usages, isExpanded: $unselectedExpanded, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope, expandProcessColumn: true)
                                Divider().padding(.leading, dividerInset)
                                if unselectedExpanded {
                                    ForEach(unselectedAppGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                        monitorAppGroupRows(group, allowManualDrag: false)
                                        Divider().padding(.leading, dividerInset + 14)
                                    }
                                }
                            }

                            if !hiddenAppGroups.isEmpty {
                                let usages = hiddenAppGroups.map(\.usage)
                                TrafficGroupRow(title: t("hiddenApps"), count: usages.count, usages: usages, isExpanded: $hiddenExpanded, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope, expandProcessColumn: true)
                                Divider().padding(.leading, dividerInset)
                                if hiddenExpanded {
                                    ForEach(hiddenAppGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                        monitorAppGroupRows(group, allowManualDrag: false, hidden: true)
                                        Divider().padding(.leading, dividerInset + 14)
                                    }
                                }
                            }

                            if shouldShowLocalGroup && !localNetworkGroups.isEmpty {
                                let usages = localNetworkGroups.map(\.usage)
                                TrafficGroupRow(title: t("localNetwork"), count: usages.count, usages: usages, isExpanded: $localExpanded, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: scale, columns: displayColumns, scope: .local, expandProcessColumn: true)
                                Divider().padding(.leading, dividerInset)
                                if localExpanded {
                                    ForEach(localNetworkGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                        monitorAppGroupRows(group, allowManualDrag: false, scope: .local)
                                        Divider().padding(.leading, dividerInset + 14)
                                    }
                                }
                            }

                            if shouldShowUnknownGroup && !unknownNetworkGroups.isEmpty {
                                let usages = unknownNetworkGroups.map(\.usage)
                                TrafficGroupRow(title: t("unclassifiedNetwork"), count: usages.count, usages: usages, isExpanded: $unknownExpanded, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: scale, columns: displayColumns, scope: .unknown, expandProcessColumn: true)
                                Divider().padding(.leading, dividerInset)
                                if unknownExpanded {
                                    ForEach(unknownNetworkGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                        monitorAppGroupRows(group, allowManualDrag: false, scope: .unknown)
                                        Divider().padding(.leading, dividerInset + 14)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .animation(removalAnimation, value: visibleUsageIDs)

            if settings.effectiveMonitorShowData && (settings.dataLimitEnabled || settings.sessionEnabled) {
                Divider()
                HStack(spacing: 12) {
                    if settings.dataLimitEnabled {
                        Label(dataLimitSummary, systemImage: "gauge.with.dots.needle.33percent")
                    }
                    if settings.sessionEnabled {
                        Spacer()
                        Text("\(t("session"))  \(SpeedFormatter.bytes(recorder.sessionTotal.download + recorder.sessionTotal.upload))")
                    }
                }
                .font(.system(size: 11.5 * scale))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14 * scale)
                .padding(.vertical, 8 * scale)
            }
        }
        .frame(minWidth: statusWindowRecommendedWidth(columns: displayColumns, processMode: settings.effectiveMonitorProcessDisplay, unitMode: settings.effectiveMonitorUnitMode, directionDisplay: settings.effectiveMonitorDirectionDisplay, scale: settings.effectiveMonitorScale.factor, language: settings.language), minHeight: 260)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { now in
            guard settings.resourceMode != .austerity else { return }
            visibilityClock = now
        }
        .onAppear {
            resetRateSampling(with: traffic.usages)
            syncManualOrderIfNeeded()
        }
        .onReceive(traffic.$usages) { usages in
            acceptTrafficSample(usages)
        }
        .onChange(of: settings.effectiveMonitorRefreshIntervalSeconds) { _ in
            resetRateSampling(with: traffic.usages)
        }
        .onChange(of: displayedUsages.map(\.id)) { _ in syncManualOrderIfNeeded() }
        .onChange(of: settings.effectiveMonitorSortMode) { _ in syncManualOrderIfNeeded() }
        .sheet(item: $expertDetailUsage) { usage in
            ExpertProcessDetailSheet(usage: usage)
        }
    }

    private func resetRateSampling(with usages: [AppNetworkUsage]) {
        rateBaseline = appUsageCounterBaseline(usages)
        rateBaselineDate = Date()
        displayedUsages = usages.map {
            AppNetworkUsage(id: $0.id,
                            displayName: $0.displayName,
                            bundleIdentifier: $0.bundleIdentifier,
                            icon: $0.icon,
                            isSystemProcess: $0.isSystemProcess,
                            isAppleApp: $0.isAppleApp,
                            downloadBytesPerSecond: 0,
                            uploadBytesPerSecond: 0,
                            cumulativeDownloadBytes: $0.cumulativeDownloadBytes,
                            cumulativeUploadBytes: $0.cumulativeUploadBytes,
                            lastActiveAt: $0.lastActiveAt)
        }
        lowActivityTracker.reset()
        lowActivityTracker.record(usages: applyingManualParentMappings(usages, mappings: settings.manualParentAppMappings), at: Date(), retention: lowActivityWindowSeconds)
        updateStableUsageOrder(using: displayedUsages)
    }

    private func acceptTrafficSample(_ usages: [AppNetworkUsage]) {
        guard settings.resourceMode != .austerity else { return }
        let now = Date()
        let interval = SettingsStore.normalizeInterval(settings.effectiveMonitorRefreshIntervalSeconds)
        let elapsed = now.timeIntervalSince(rateBaselineDate)

        // The v0.5.0 provider uses sparse byte checkpoints so cumulative app counters
        // can legitimately stay unchanged across a 0.25 s UI poll even while a small
        // amount of traffic is passing inside an already-authorized window. Do not
        // move the baseline on that single empty poll; otherwise the next checkpoint
        // could be divided by too short an interval and appear as a false speed spike.
        let countersChanged = appUsageCountersChanged(usages, from: rateBaseline)
        if !countersChanged {
            // Once a reasonable quiet window has passed without a counter change, publish
            // a true zero and reset the baseline so traffic resuming later is not
            // averaged across a long idle period.
            guard elapsed >= max(interval, 0.75) else { return }
            displayedUsages = resampledAppNetworkUsages(usages, from: rateBaseline, elapsed: elapsed)
            lowActivityTracker.record(usages: applyingManualParentMappings(usages, mappings: settings.manualParentAppMappings), at: now, retention: lowActivityWindowSeconds)
            updateStableUsageOrder(using: displayedUsages)
            rateBaseline = appUsageCounterBaseline(usages)
            rateBaselineDate = now
            return
        }

        guard elapsed >= interval else { return }
        displayedUsages = resampledAppNetworkUsages(usages, from: rateBaseline, elapsed: elapsed)
        lowActivityTracker.record(usages: applyingManualParentMappings(usages, mappings: settings.manualParentAppMappings), at: now, retention: lowActivityWindowSeconds)
        updateStableUsageOrder(using: displayedUsages)
        rateBaseline = appUsageCounterBaseline(usages)
        rateBaselineDate = now
    }


    @ViewBuilder
    private func monitorTrafficRow(_ usage: AppNetworkUsage,
                                   indented: Bool,
                                   allowManualDrag: Bool,
                                   hidden: Bool = false,
                                   scope: TrafficValueScope? = nil,
                                   disclosureExpanded: Bool? = nil,
                                   disclosureOnTrailingEdge: Bool = false,
                                   onToggleDisclosure: (() -> Void)? = nil) -> some View {
        LiveTrafficRow(usage: usage,
                       processMode: settings.effectiveMonitorProcessDisplay,
                       unitMode: settings.effectiveMonitorUnitMode,
                       directionDisplay: settings.effectiveMonitorDirectionDisplay,
                       scale: scale,
                       columns: displayColumns,
                       scope: scope ?? mainTrafficScope,
                       indent: indented ? 14 : 0,
                       disclosureExpanded: disclosureExpanded,
                       disclosureOnTrailingEdge: disclosureOnTrailingEdge,
                       onToggleDisclosure: onToggleDisclosure,
                       expandProcessColumn: true)
            .background(selectedTrafficID == usage.id ? NeManeemTheme.accent.opacity(0.14) : Color.clear)
            .overlay(alignment: .top) {
                if allowManualDrag && dropTargetID == usage.id {
                    Rectangle()
                        .fill(NeManeemTheme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedTrafficID = usage.id }
            .accessibilityAction { selectedTrafficID = usage.id }
            .contextMenu {
                AppIdentityContextMenuContent(usage: usage, preferProcess: false)
                Divider()
                if expertFeaturesActive {
                    Button(t("copyInformation")) { copyUsageInformation(usage, preferProcess: false) }
                    Button(t("processDetails")) { expertDetailUsage = usage }
                    Divider()
                }
                if settings.effectiveMonitorVisibilityMode == .selectedOnly {
                    if Set(settings.effectiveMonitorSelectedProcessIDs).contains(usage.id) {
                        Button(t("removeFromSelection")) { settings.setProcessSelected(usage.id, selected: false, monitor: true) }
                    } else {
                        Button(t("addToSelection")) { settings.setProcessSelected(usage.id, selected: true, monitor: true) }
                    }
                } else if hidden {
                    Button(t("showAppAgain")) { settings.setProcessHidden(usage.id, hidden: false, monitor: true) }
                } else {
                    Button(t("hideApp")) { settings.setProcessHidden(usage.id, hidden: true, monitor: true) }
                }
            }
            .if(allowManualDrag) { view in
                view
                    .onDrag {
                        draggingID = usage.id
                        return NSItemProvider(object: usage.id as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: ManualTrafficOrderDropDelegate(
                        targetID: usage.id,
                        draggingID: $draggingID,
                        dropTargetID: $dropTargetID,
                        onMove: { source, target in settings.moveManualProcess(source, before: target, monitor: true) }
                    ))
            }
            .transition(rowTransition)
    }

    @ViewBuilder
    private func monitorAppGroupRows(_ group: AppUsageGroup,
                                     allowManualDrag: Bool,
                                     hidden: Bool = false,
                                     scope: TrafficValueScope? = nil) -> some View {
        let safariCompatibilityExpansion = settings.safariNetworkServiceGroupingEnabled && group.usage.isSafari && group.members.contains(where: isSafariNetworkServiceUsage)
        let canExpand = (expertFeaturesActive && group.isExpandable) || safariCompatibilityExpansion
        let expanded = canExpand && expandedAppIDs.contains(group.id)
        monitorTrafficRow(group.usage,
                          indented: false,
                          allowManualDrag: allowManualDrag,
                          hidden: hidden,
                          scope: scope,
                          disclosureExpanded: canExpand ? expanded : nil,
                          disclosureOnTrailingEdge: safariCompatibilityExpansion,
                          onToggleDisclosure: canExpand ? {
                              if expanded { expandedAppIDs.remove(group.id) } else { expandedAppIDs.insert(group.id) }
                          } : nil)

        if canExpand && expanded {
            ForEach(group.members.filter { !settings.hiddenDetailProcessIDs.contains($0.id) }) { member in
                LiveTrafficRow(usage: member,
                               processMode: settings.effectiveMonitorProcessDisplay,
                               unitMode: settings.effectiveMonitorUnitMode,
                               directionDisplay: settings.effectiveMonitorDirectionDisplay,
                               scale: scale,
                               columns: displayColumns,
                               scope: scope ?? mainTrafficScope,
                               indent: 22,
                               isProcessDetail: true,
                               allowsBlocking: false,
                               expandProcessColumn: true)
                    .background(selectedTrafficID == member.id ? NeManeemTheme.accent.opacity(0.14) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedTrafficID = member.id }
                    .accessibilityAction { selectedTrafficID = member.id }
                    .contextMenu {
                        AppIdentityContextMenuContent(usage: member, preferProcess: true)
                        Divider()
                        if expertFeaturesActive {
                            Button(t("copyInformation")) { copyUsageInformation(member, preferProcess: true) }
                            Button(t("processDetails")) { expertDetailUsage = member }
                            if settings.advancedProcessControlsEnabled {
                                Divider()
                                Button(t("hideProcessDetail")) { settings.setDetailProcessHidden(member.id, hidden: true) }
                            }
                        }
                    }
                Divider().padding(.leading, dividerInset + 22)
            }
        }
    }

    private var activeFilteredUsages: [AppNetworkUsage] {
        let base: [AppNetworkUsage]
        if settings.effectiveMonitorHideInactiveApps {
            let seconds = SettingsStore.normalizeInactiveHideDelay(settings.effectiveMonitorInactiveHideDelaySeconds)
            base = displayedUsages.filter { usage in
                if usage.isActive { return true }
                return visibilityClock.timeIntervalSince(usage.lastActiveAt) <= seconds
            }
        } else {
            base = displayedUsages
        }

        let mappedBase = applyingManualParentMappings(base, mappings: settings.manualParentAppMappings)
        guard expertFeaturesActive else { return mappedBase }
        let query = expertSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return mappedBase.filter { usage in
            let searchMatches = query.isEmpty ||
                usage.displayName.localizedCaseInsensitiveContains(query) ||
                (usage.appDisplayName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (usage.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false) ||
                (usage.processIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
            guard searchMatches else { return false }
            switch expertFilter {
            case .all: return true
            case .internet: return usage.internetDownloadBytesPerSecond &+ usage.internetUploadBytesPerSecond > 0
            case .local: return usage.localDownloadBytesPerSecond &+ usage.localUploadBytesPerSecond > 0
            case .unknown: return usage.unknownDownloadBytesPerSecond &+ usage.unknownUploadBytesPerSecond > 0
            }
        }
    }

    private var expertFeaturesActive: Bool {
        settings.expertFeaturesEnabled && settings.resourceMode != .austerity
    }

    private var expertSortBinding: Binding<TrafficSortMode> {
        Binding(
            get: { settings.effectiveMonitorSortMode },
            set: { newValue in
                if settings.monitorUsePopoverSettings {
                    settings.popoverSortMode = newValue
                } else {
                    settings.monitorSortMode = newValue
                }
            }
        )
    }

    private var expertToolbar: some View {
        HStack(spacing: 8) {
            Text(t("expertFeatureBadge"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NeManeemTheme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(NeManeemTheme.accent.opacity(0.10), in: Capsule())

            TextField(t("expertSearch"), text: $expertSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Picker(t("expertFilter"), selection: $expertFilter) {
                Text(t("expertFilterAll")).tag(ExpertTrafficFilter.all)
                Text(t("expertFilterInternet")).tag(ExpertTrafficFilter.internet)
                Text(t("expertFilterLocal")).tag(ExpertTrafficFilter.local)
                Text(t("expertFilterUnknown")).tag(ExpertTrafficFilter.unknown)
            }
            .labelsHidden()
            .pickerStyle(.menu)
                .nmNeutralValueControl()
            .frame(width: 120)

            Picker(t("sortBy"), selection: expertSortBinding) {
                Text(t("sortCurrentUsage")).tag(TrafficSortMode.currentUsage)
                Text(t("download")).tag(TrafficSortMode.download)
                Text(t("upload")).tag(TrafficSortMode.upload)
                Text(t("processName")).tag(TrafficSortMode.name)
                Text(t("sortManual")).tag(TrafficSortMode.manual)
            }
            .labelsHidden()
            .pickerStyle(.menu)
                .nmNeutralValueControl()
            .frame(width: 128)

            Spacer(minLength: 6)
            Button { exportCurrentTrafficCSV() } label: {
                Label(t("exportLiveCSV"), systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func copyUsageInformation(_ usage: AppNetworkUsage, preferProcess: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(usageInformationText(usage, preferProcess: preferProcess), forType: .string)
    }

    private func usageInformationText(_ usage: AppNetworkUsage, preferProcess: Bool) -> String {
        var lines = ["\(t("processName")): \(usage.displayName)"]
        if let app = usage.appDisplayName, !app.isEmpty, app != usage.displayName {
            lines.append("\(t("applicationName")): \(app)")
        }
        if let bundle = usage.bundleIdentifier, !bundle.isEmpty {
            lines.append("\(t("bundleIdentifier")): \(bundle)")
        }
        if let process = usage.processIdentifier, !process.isEmpty {
            lines.append("\(t("processIdentifier")): \(process)")
        }
        if let location = AppLocationResolver.resolve(usage, preferProcess: preferProcess) {
            lines.append("\(t("applicationPath")): \(location.url.path)")
        }
        lines.append("\(t("currentDownload")): \(SpeedFormatter.string(bytesPerSecond: usage.downloadBytesPerSecond, mode: .bytesPerSecond))")
        lines.append("\(t("currentUpload")): \(SpeedFormatter.string(bytesPerSecond: usage.uploadBytesPerSecond, mode: .bytesPerSecond))")
        lines.append("\(t("measurementTotal")): \(SpeedFormatter.bytes(usage.cumulativeDownloadBytes &+ usage.cumulativeUploadBytes))")
        return lines.joined(separator: "\n")
    }

    private func exportCurrentTrafficCSV() {
        let panel = NSSavePanel()
        panel.title = t("exportLiveCSV")
        panel.nameFieldStringValue = "NeManeem-live-traffic.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var rows = [[t("processName"), t("bundleIdentifier"), t("processIdentifier"), t("currentDownload"), t("currentUpload"), t("measurementTotal")]]
        for usage in activeFilteredUsages {
            rows.append([
                usage.displayName,
                usage.bundleIdentifier ?? "",
                usage.processIdentifier ?? "",
                String(usage.downloadBytesPerSecond),
                String(usage.uploadBytesPerSecond),
                String(usage.cumulativeDownloadBytes &+ usage.cumulativeUploadBytes)
            ])
        }
        let csv = rows.map { $0.map(csvEscaped).joined(separator: ",") }.joined(separator: "\n") + "\n"
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private var selectedProcessIDs: Set<String> { Set(settings.effectiveMonitorSelectedProcessIDs) }
    private var hiddenProcessIDs: Set<String> { Set(settings.effectiveMonitorHiddenProcessIDs) }
    private var lowActivityWindowSeconds: TimeInterval {
        SettingsStore.normalizeLowActivityDuration(settings.effectiveMonitorLowActivityDurationValue) * settings.effectiveMonitorLowActivityDurationUnit.secondsMultiplier
    }

    private var lowActivityThresholdBytes: UInt64 {
        UInt64(SettingsStore.normalizeLowActivityData(settings.effectiveMonitorLowActivityDataValue) * settings.effectiveMonitorLowActivityDataUnit.byteMultiplier)
    }

    private func isLowActivity(_ group: AppUsageGroup) -> Bool {
        guard let transferred = lowActivityTracker.transferredBytes(for: group.id,
                                                                    duration: lowActivityWindowSeconds,
                                                                    now: visibilityClock) else { return false }
        return transferred <= lowActivityThresholdBytes
    }

    private var activeClassifiedUsages: AppSystemUsageSplit {
        splitAppAndSystemUsages(activeFilteredUsages)
    }

    private var activeAppGroups: [AppUsageGroup] {
        appUsageGroups(activeClassifiedUsages.apps)
    }

    private var hiddenAppGroups: [AppUsageGroup] {
        guard settings.effectiveMonitorVisibilityMode == .allApps else { return [] }
        return activeAppGroups.filter { appGroupMatchesHidden($0, hiddenIDs: hiddenProcessIDs) }
    }

    private var rawSystemUsages: [AppNetworkUsage] {
        guard settings.effectiveMonitorGroupSystemProcesses else { return [] }
        return activeClassifiedUsages.systemServices.filter { usage in
            if settings.effectiveMonitorVisibilityMode == .selectedOnly {
                return isAppUsageSelected(usage, selectedIDs: selectedProcessIDs)
            }
            return !hiddenProcessIDs.contains(usage.id)
        }
    }

    private var rawUngroupedSystemUsages: [AppNetworkUsage] {
        guard !settings.effectiveMonitorGroupSystemProcesses else { return [] }
        return activeClassifiedUsages.systemServices.filter { usage in
            if settings.effectiveMonitorVisibilityMode == .selectedOnly {
                return isAppUsageSelected(usage, selectedIDs: selectedProcessIDs)
            }
            return !hiddenProcessIDs.contains(usage.id)
        }
    }

    private var systemUsages: [AppNetworkUsage] {
        expertFeaturesActive ? rawSystemUsages : collapsedSystemServiceUsages(rawSystemUsages)
    }

    private var ungroupedSystemUsages: [AppNetworkUsage] {
        expertFeaturesActive ? rawUngroupedSystemUsages : collapsedSystemServiceUsages(rawUngroupedSystemUsages)
    }

    private var lowActivityAppGroups: [AppUsageGroup] {
        guard settings.effectiveMonitorVisibilityMode == .allApps, settings.effectiveMonitorHideLowActivityApps else { return [] }
        return activeAppGroups.filter { group in
            if appGroupMatchesHidden(group, hiddenIDs: hiddenProcessIDs) { return false }
            return isLowActivity(group)
        }
    }

    private var unselectedAppGroups: [AppUsageGroup] {
        guard settings.effectiveMonitorVisibilityMode == .selectedOnly, settings.effectiveMonitorGroupUnselectedApps else { return [] }
        return activeAppGroups.filter { !appGroupMatchesSelection($0, selectedIDs: selectedProcessIDs) }
    }

    private var normalAppGroups: [AppUsageGroup] {
        let values: [AppUsageGroup]
        if settings.effectiveMonitorVisibilityMode == .selectedOnly {
            values = activeAppGroups.filter { appGroupMatchesSelection($0, selectedIDs: selectedProcessIDs) }
        } else {
            values = activeAppGroups.filter { group in
                if appGroupMatchesHidden(group, hiddenIDs: hiddenProcessIDs) { return false }
                if settings.effectiveMonitorHideLowActivityApps && isLowActivity(group) { return false }
                return true
            }
        }
        if settings.effectiveMonitorSortMode == .currentUsage {
            let index = Dictionary(uniqueKeysWithValues: stableUsageOrder.enumerated().map { ($0.element, $0.offset) })
            return values.sorted {
                let li = index[$0.id] ?? Int.max
                let ri = index[$1.id] ?? Int.max
                if li == ri { return $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }
                return li < ri
            }
        }
        let sorted = sortedTrafficUsages(values.map(\.usage),
                                         by: settings.effectiveMonitorSortMode,
                                         manualOrder: settings.effectiveMonitorManualOrder)
        let map = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        return sorted.compactMap { map[$0.id] }
    }

    private func updateStableUsageOrder(using usages: [AppNetworkUsage]) {
        let groups = appUsageGroups(splitAppAndSystemUsages(usages).apps)
        let previous = Dictionary(uniqueKeysWithValues: stableUsageOrder.enumerated().map { ($0.element, $0.offset) })
        stableUsageOrder = groups.sorted { lhs, rhs in
            let lb = usageActivityBand(lhs.usage.totalBytesPerSecond)
            let rb = usageActivityBand(rhs.usage.totalBytesPerSecond)
            if lb != rb { return lb > rb }
            let li = previous[lhs.id] ?? Int.max
            let ri = previous[rhs.id] ?? Int.max
            if li != ri { return li < ri }
            return lhs.usage.displayName.localizedCaseInsensitiveCompare(rhs.usage.displayName) == .orderedAscending
        }.map(\.id)
    }

    private func usageActivityBand(_ value: UInt64) -> Int {
        guard value > 0 else { return -1 }
        return Int(floor(log10(Double(value))))
    }

    private var localNetworkGroups: [AppUsageGroup] {
        var values = activeFilteredUsages.filter { ($0.localDownloadBytesPerSecond &+ $0.localUploadBytesPerSecond) > 0 }
        if let fallback = conservativeLocalNetworkFallbackUsage(interface: interface.snapshot,
                                                                 usages: activeFilteredUsages,
                                                                 displayName: t("localNetworkActivity")) {
            values.append(fallback)
        }
        return appUsageGroups(values)
    }

    private var unknownNetworkGroups: [AppUsageGroup] {
        appUsageGroups(activeFilteredUsages.filter { ($0.unknownDownloadBytesPerSecond &+ $0.unknownUploadBytesPerSecond) > 0 })
    }

    private var visibleUsageIDs: [String] {
        normalAppGroups.map(\.id) + systemUsages.map(\.id) + ungroupedSystemUsages.map(\.id) +
        lowActivityAppGroups.map(\.id) + unselectedAppGroups.map(\.id) + hiddenAppGroups.map(\.id) +
        (shouldShowLocalGroup ? localNetworkGroups.map(\.id) : []) +
        (shouldShowUnknownGroup ? unknownNetworkGroups.map(\.id) : [])
    }

    private var mainTrafficScope: TrafficValueScope {
        guard settings.separateLocalTraffic else { return .all }
        return settings.localTrafficStatisticsMode == .combined ? .all : .internet
    }

    private var shouldShowLocalGroup: Bool {
        settings.separateLocalTraffic && settings.localTrafficStatisticsMode == .separate
    }

    private var shouldShowUnknownGroup: Bool {
        settings.separateLocalTraffic && settings.localTrafficStatisticsMode != .combined
    }

    private func syncManualOrderIfNeeded() {
        guard settings.effectiveMonitorSortMode == .manual else { return }
        settings.ensureManualOrderContains(appUsageGroups(activeFilteredUsages).map(\.id), monitor: true)
    }

    private var stateMessage: String? {
        if settings.resourceMode == .austerity { return t("austerityAppListPaused") }
        if traffic.hasPersistentConnectionError { return t("measurementEngineUnavailable") }
        if !traffic.hasCompletedInitialSample { return t("checkingActivity") }
        if visibleUsageIDs.isEmpty && !activeFilteredUsages.isEmpty { return t("noVisibleApps") }
        return visibleUsageIDs.isEmpty ? t("noActivity") : nil
    }

    private var rowTransition: AnyTransition {
        guard settings.effectiveMonitorExitMotion && !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity))
    }

    private var removalAnimation: Animation? {
        guard settings.effectiveMonitorExitMotion && !reduceMotion else { return .easeOut(duration: 0.12) }
        return .easeInOut(duration: 0.24)
    }

    private var dividerInset: CGFloat { settings.effectiveMonitorProcessDisplay == .nameOnly ? 14 : 46 }

    private var dataLimitSummary: String {
        let used = recorder.currentCycleTotal.download + recorder.currentCycleTotal.upload
        let limit = settings.dataLimitBytes
        let value = settings.dataLimitDisplayMode == .used ? used : (limit > used ? limit - used : 0)
        let label = t(settings.dataLimitDisplayMode == .used ? "used" : "remaining")
        return "\(label)  \(SpeedFormatter.bytes(value)) / \(SpeedFormatter.bytes(limit))"
    }
}

private struct ExpertProcessDetailSheet: View {
    let usage: AppNetworkUsage
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @Environment(\.dismiss) private var dismiss

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: usage.icon).resizable().scaledToFit().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(usage.displayName).font(.title3.weight(.semibold))
                    Text(t("expertFeatureBadge")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                detailRow(t("applicationName"), usage.appDisplayName ?? usage.displayName)
                detailRow(t("bundleIdentifier"), usage.bundleIdentifier ?? "—")
                detailRow(t("processIdentifier"), usage.processIdentifier ?? "—")
                detailRow(t("applicationPath"), resolvedPath ?? "—")
                detailRow(t("currentDownload"), SpeedFormatter.string(bytesPerSecond: usage.downloadBytesPerSecond, mode: .bytesPerSecond))
                detailRow(t("currentUpload"), SpeedFormatter.string(bytesPerSecond: usage.uploadBytesPerSecond, mode: .bytesPerSecond))
                detailRow(t("measurementTotal"), SpeedFormatter.bytes(usage.cumulativeDownloadBytes &+ usage.cumulativeUploadBytes))
                detailRow(t("expertFilterInternet"), SpeedFormatter.string(bytesPerSecond: usage.internetDownloadBytesPerSecond &+ usage.internetUploadBytesPerSecond, mode: .bytesPerSecond))
                detailRow(t("expertFilterLocal"), SpeedFormatter.string(bytesPerSecond: usage.localDownloadBytesPerSecond &+ usage.localUploadBytesPerSecond, mode: .bytesPerSecond))
                detailRow(t("expertFilterUnknown"), SpeedFormatter.string(bytesPerSecond: usage.unknownDownloadBytesPerSecond &+ usage.unknownUploadBytesPerSecond, mode: .bytesPerSecond))
            }

            HStack {
                Button(t("copyInformation")) { copyAll() }
                if let location = AppLocationResolver.resolve(usage, preferProcess: true) {
                    Button(location.isProcessSpecific ? t("revealProcessInFinder") : t("revealAppInFinder")) {
                        AppLocationResolver.reveal(location)
                    }
                }
                Spacer()
                Button(t("close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private var resolvedPath: String? {
        AppLocationResolver.resolve(usage, preferProcess: true)?.url.path
    }

    private func copyAll() {
        var lines = ["\(t("processName")): \(usage.displayName)",
                     "\(t("bundleIdentifier")): \(usage.bundleIdentifier ?? "—")",
                     "\(t("processIdentifier")): \(usage.processIdentifier ?? "—")",
                     "\(t("applicationPath")): \(resolvedPath ?? "—")",
                     "\(t("currentDownload")): \(SpeedFormatter.string(bytesPerSecond: usage.downloadBytesPerSecond, mode: .bytesPerSecond))",
                     "\(t("currentUpload")): \(SpeedFormatter.string(bytesPerSecond: usage.uploadBytesPerSecond, mode: .bytesPerSecond))",
                     "\(t("measurementTotal")): \(SpeedFormatter.bytes(usage.cumulativeDownloadBytes &+ usage.cumulativeUploadBytes))"]
        if let app = usage.appDisplayName, !app.isEmpty { lines.insert("\(t("applicationName")): \(app)", at: 1) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

