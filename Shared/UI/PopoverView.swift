import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct StatusTableMetrics {
    let processWidth: CGFloat
    let metricWidth: CGFloat
    let usageWidth: CGFloat
    let controlWidth: CGFloat
    let spacing: CGFloat
    let horizontalPadding: CGFloat

    func width(for column: StatusColumn) -> CGFloat {
        switch column {
        case .process: return processWidth
        case .download, .upload: return metricWidth
        case .today, .week, .month, .session, .dataCycle: return usageWidth
        case .allowed: return controlWidth
        }
    }

    func totalWidth(columns: [StatusColumn]) -> CGFloat {
        let safeColumns = columns.isEmpty ? StatusColumn.defaultColumns : columns
        let content = safeColumns.reduce(CGFloat(0)) { $0 + width(for: $1) }
        return content + CGFloat(max(0, safeColumns.count - 1)) * spacing + horizontalPadding * 2
    }
}

private func statusTextWidth(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return ceil((text as NSString).size(withAttributes: [.font: font]).width)
}

private func statusTableMetrics(processMode: ProcessDisplayMode,
                                unitMode: SpeedUnitMode,
                                directionDisplay: TransferDirectionDisplay,
                                scale: CGFloat,
                                language: AppLanguage) -> StatusTableMetrics {
    let rowSize = 12.5 * scale
    let headerSize = 11.5 * scale
    let t: (String) -> String = { L10n.text($0, language: language) }

    let directionHeaders = directionDisplay == .words ? [t("download"), t("upload")] : ["↓", "↑"]
    let metricText = max(statusTextWidth(SpeedFormatter.maximumStatusSample(for: unitMode), size: rowSize),
                         directionHeaders.map { statusTextWidth($0, size: headerSize, weight: .medium) }.max() ?? 0)
    let usageHeaders = ["today", "thisWeek", "thisMonth", "session", "dataCycle"].map(t)
    let usageText = max(statusTextWidth(SpeedFormatter.maximumStatusByteSample(), size: rowSize),
                        usageHeaders.map { statusTextWidth($0, size: headerSize, weight: .medium) }.max() ?? 0)

    // The app column deliberately has a compact name budget. Long app names use
    // ellipsis; increasing the user's display size increases this minimum width.
    let nameBudget = ceil(rowSize * 7.2)
    let disclosure = 11 * scale
    let icon = processMode == .nameOnly ? 0 : 20 * scale
    let internalGaps: CGFloat = processMode == .iconOnly ? 12 * scale : 18 * scale
    let processWidth: CGFloat
    switch processMode {
    case .iconOnly:
        processWidth = max(statusTextWidth(t("processName"), size: headerSize, weight: .medium), disclosure + icon + internalGaps)
    case .nameOnly:
        processWidth = max(72 * scale, nameBudget + disclosure + internalGaps)
    case .iconAndName:
        processWidth = max(92 * scale, nameBudget + disclosure + icon + internalGaps)
    }

    let blockWidth = max(42 * scale, statusTextWidth(t("allowed"), size: headerSize, weight: .medium) + 8)
    return StatusTableMetrics(processWidth: ceil(processWidth),
                              metricWidth: ceil(metricText + 6),
                              usageWidth: ceil(usageText + 6),
                              controlWidth: ceil(blockWidth),
                              spacing: max(5, 7 * scale),
                              horizontalPadding: max(10, 12 * scale))
}

func statusWindowRecommendedWidth(columns: [StatusColumn],
                                  processMode: ProcessDisplayMode,
                                  unitMode: SpeedUnitMode,
                                  directionDisplay: TransferDirectionDisplay,
                                  scale: CGFloat,
                                  language: AppLanguage) -> CGFloat {
    let metrics = statusTableMetrics(processMode: processMode,
                                     unitMode: unitMode,
                                     directionDisplay: directionDisplay,
                                     scale: scale,
                                     language: language)
    return min(980, max(210, metrics.totalWidth(columns: columns)))
}


struct PopoverView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var traffic = AppEnvironment.shared.appTrafficMonitor
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @ObservedObject private var interface = AppEnvironment.shared.interfaceMonitor
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

    let openMainWindow: (MainWindowMode) -> Void

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }
    private var scale: CGFloat { settings.popoverScale.factor }
    private var displayColumns: [StatusColumn] { activeStatusColumns(settings.popoverColumns, appBlockingEnabled: firewall.isEnabled) }
    private var popoverWidth: CGFloat {
        statusWindowRecommendedWidth(columns: displayColumns,
                                     processMode: settings.popoverProcessDisplay,
                                     unitMode: settings.popoverUnitMode,
                                     directionDisplay: settings.popoverDirectionDisplay,
                                     scale: scale,
                                     language: settings.language)
    }

    @ViewBuilder
    var body: some View {
        if settings.resourceMode == .austerity {
            AusterityPopoverView(openMainWindow: openMainWindow)
        } else {
            standardPopoverBody
        }
    }

    private var standardPopoverBody: some View {
        VStack(spacing: 0) {
            if settings.popoverShowTotalSpeed {
                TrafficSummaryRow(title: t("overall"),
                                  download: interface.snapshot.downloadBytesPerSecond,
                                  upload: interface.snapshot.uploadBytesPerSecond,
                                  processMode: settings.popoverProcessDisplay,
                                  unitMode: settings.popoverUnitMode,
                                  directionDisplay: settings.popoverDirectionDisplay,
                                  scale: scale,
                                  columns: displayColumns)
                Divider()
            }

            trafficTable
                .frame(minHeight: 230, maxHeight: 390)

            if (settings.showDataLimitInPopover && settings.dataLimitEnabled) || settings.showSessionInPopover {
                Divider()
                CompactDataSessionArea(unitMode: settings.popoverUnitMode, horizontalPadding: 14)
            }

            Divider()
            HStack(spacing: 0) {
                Button { openMainWindow(.standard) } label: {
                    Image(systemName: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(NMInlineActionButtonStyle())
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
                .help(t("settings"))
                .accessibilityLabel(t("settings"))

                Button(t("windowMode")) { openMainWindow(.monitor) }
                    .buttonStyle(NMInlineActionButtonStyle())
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .help(t("windowView"))
                    .accessibilityLabel(t("windowView"))

                Button(t("quit")) { NSApp.terminate(nil) }
                    .buttonStyle(NMInlineActionButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentShape(Rectangle())
                    .help(t("quit"))
                    .accessibilityLabel(t("quit"))
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        // Each column uses only the minimum width required by the selected font,
        // label style and data type. Larger text or additional columns may grow the
        // outer popover instead of crushing the contents.
        .frame(width: popoverWidth)
        .tint(NeManeemTheme.accent)
        .animation(removalAnimation, value: visibleUsageIDs)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { now in
            // 긴축 모드에서는 앱 행 자체를 유지하지 않으므로 숨김 판단용 시계도 건드리지 않습니다.
            guard settings.resourceMode != .austerity else { return }
            // Row disappearance has its own lightweight clock. It never triggers a
            // network sample, so data refresh cadence and visual cleanup are independent.
            visibilityClock = now
        }
        .onAppear {
            resetRateSampling(with: traffic.usages, preserveRates: traffic.hasCompletedInitialSample)
            syncManualOrderIfNeeded()
        }
        // AppTrafficMonitor polls the exact cumulative counters at the fastest
        // active requirement. This view derives its own rate only when its chosen
        // interval has elapsed, so 0.25 s / 3 s / 10 s are real sampling windows
        // rather than cosmetic repaint speeds. No second UI timer is needed.
        .onReceive(traffic.$usages) { usages in
            acceptTrafficSample(usages)
        }
        .onChange(of: settings.effectivePopoverRefreshIntervalSeconds) { _ in
            resetRateSampling(with: traffic.usages)
        }
        .onChange(of: displayedUsages.map(\.id)) { _ in syncManualOrderIfNeeded() }
        .onChange(of: settings.popoverSortMode) { _ in syncManualOrderIfNeeded() }
    }

    private func resetRateSampling(with usages: [AppNetworkUsage], preserveRates: Bool = false) {
        rateBaseline = appUsageCounterBaseline(usages)
        rateBaselineDate = Date()
        if preserveRates {
            displayedUsages = usages
            lowActivityTracker.record(usages: applyingManualParentMappings(usages, mappings: settings.manualParentAppMappings), at: Date(), retention: lowActivityWindowSeconds)
            updateStableUsageOrder(using: displayedUsages)
        } else {
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
    }

    private func acceptTrafficSample(_ usages: [AppNetworkUsage]) {
        guard settings.resourceMode != .austerity else { return }
        let now = Date()
        let interval = SettingsStore.normalizeInterval(settings.effectivePopoverRefreshIntervalSeconds)
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

    private var trafficTable: some View {
        VStack(spacing: 0) {
            TrafficTableHeader(
                processMode: settings.popoverProcessDisplay,
                unitMode: settings.popoverUnitMode,
                directionDisplay: settings.popoverDirectionDisplay,
                scale: scale,
                columns: displayColumns
            )
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

                    if firewall.monitoringPermissionRequestRecommended {
                        VStack(spacing: 7) {
                            Text(t("networkPermissionPendingHelp"))
                                .font(.system(size: 11.5 * scale))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Button(t("requestNetworkPermission")) {
                                    firewall.requestMonitoringPermission()
                                }
                                .buttonStyle(NMNeutralActionButtonStyle())
                                .controlSize(.small)
                                .disabled(firewall.isBusy)
                                Button(t("troubleshootShortcut")) {
                                    AppEnvironment.shared.requestSettingsSection?("troubleshooting")
                                }
                                .buttonStyle(NMNeutralActionButtonStyle())
                                .controlSize(.small)
                            }
                        }
                    } else if traffic.connectionFailureCount >= 3 {
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
                            appGroupRows(group, allowManualDrag: settings.popoverSortMode == .manual)
                            Divider().padding(.leading, processDividerInset)
                        }

                        ForEach(sortedTrafficUsages(ungroupedSystemUsages, by: settings.popoverSortMode, manualOrder: settings.popoverManualOrder)) { usage in
                            trafficRow(usage, indented: false, allowManualDrag: settings.popoverSortMode == .manual)
                            Divider().padding(.leading, processDividerInset)
                        }

                        if !systemUsages.isEmpty {
                            TrafficGroupRow(title: t("systemServices"),
                                            count: systemUsages.count,
                                            usages: systemUsages,
                                            isExpanded: $systemExpanded,
                                            processMode: settings.popoverProcessDisplay,
                                            unitMode: settings.popoverUnitMode,
                                            directionDisplay: settings.popoverDirectionDisplay,
                                            scale: scale,
                                            columns: displayColumns,
                                            scope: mainTrafficScope)
                            Divider().padding(.leading, processDividerInset)
                            if systemExpanded {
                                ForEach(sortedTrafficUsages(systemUsages, by: .name, manualOrder: [])) { usage in
                                    trafficRow(usage, indented: true, allowManualDrag: false)
                                    Divider().padding(.leading, processDividerInset + 14)
                                }
                            }
                        }

                        if !lowActivityAppGroups.isEmpty {
                            let usages = lowActivityAppGroups.map(\.usage)
                            TrafficGroupRow(title: t("lowActivityApps"), count: usages.count, usages: usages, isExpanded: $lowActivityExpanded, processMode: settings.popoverProcessDisplay, unitMode: settings.popoverUnitMode, directionDisplay: settings.popoverDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope)
                            Divider().padding(.leading, processDividerInset)
                            if lowActivityExpanded {
                                ForEach(lowActivityAppGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                    appGroupRows(group, allowManualDrag: false)
                                    Divider().padding(.leading, processDividerInset + 14)
                                }
                            }
                        }

                        if !unselectedAppGroups.isEmpty {
                            let usages = unselectedAppGroups.map(\.usage)
                            TrafficGroupRow(title: t("otherApps"), count: usages.count, usages: usages, isExpanded: $unselectedExpanded, processMode: settings.popoverProcessDisplay, unitMode: settings.popoverUnitMode, directionDisplay: settings.popoverDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope)
                            Divider().padding(.leading, processDividerInset)
                            if unselectedExpanded {
                                ForEach(unselectedAppGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                    appGroupRows(group, allowManualDrag: false)
                                    Divider().padding(.leading, processDividerInset + 14)
                                }
                            }
                        }

                        if !hiddenAppGroups.isEmpty {
                            let usages = hiddenAppGroups.map(\.usage)
                            TrafficGroupRow(title: t("hiddenApps"), count: usages.count, usages: usages, isExpanded: $hiddenExpanded, processMode: settings.popoverProcessDisplay, unitMode: settings.popoverUnitMode, directionDisplay: settings.popoverDirectionDisplay, scale: scale, columns: displayColumns, scope: mainTrafficScope)
                            Divider().padding(.leading, processDividerInset)
                            if hiddenExpanded {
                                ForEach(hiddenAppGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                    appGroupRows(group, allowManualDrag: false, hidden: true)
                                    Divider().padding(.leading, processDividerInset + 14)
                                }
                            }
                        }

                        if shouldShowLocalGroup && !localNetworkGroups.isEmpty {
                            let usages = localNetworkGroups.map(\.usage)
                            TrafficGroupRow(title: t("localNetwork"), count: usages.count, usages: usages, isExpanded: $localExpanded, processMode: settings.popoverProcessDisplay, unitMode: settings.popoverUnitMode, directionDisplay: settings.popoverDirectionDisplay, scale: scale, columns: displayColumns, scope: .local)
                            Divider().padding(.leading, processDividerInset)
                            if localExpanded {
                                ForEach(localNetworkGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                    appGroupRows(group, allowManualDrag: false, scope: .local)
                                    Divider().padding(.leading, processDividerInset + 14)
                                }
                            }
                        }

                        if shouldShowUnknownGroup && !unknownNetworkGroups.isEmpty {
                            let usages = unknownNetworkGroups.map(\.usage)
                            TrafficGroupRow(title: t("unclassifiedNetwork"), count: usages.count, usages: usages, isExpanded: $unknownExpanded, processMode: settings.popoverProcessDisplay, unitMode: settings.popoverUnitMode, directionDisplay: settings.popoverDirectionDisplay, scale: scale, columns: displayColumns, scope: .unknown)
                            Divider().padding(.leading, processDividerInset)
                            if unknownExpanded {
                                ForEach(unknownNetworkGroups.sorted { $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }) { group in
                                    appGroupRows(group, allowManualDrag: false, scope: .unknown)
                                    Divider().padding(.leading, processDividerInset + 14)
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    @ViewBuilder
    private func trafficRow(_ usage: AppNetworkUsage,
                            indented: Bool,
                            allowManualDrag: Bool,
                            hidden: Bool = false,
                            scope: TrafficValueScope? = nil,
                            disclosureExpanded: Bool? = nil,
                            disclosureOnTrailingEdge: Bool = false,
                            onToggleDisclosure: (() -> Void)? = nil) -> some View {
        LiveTrafficRow(
            usage: usage,
            processMode: settings.popoverProcessDisplay,
            unitMode: settings.popoverUnitMode,
            directionDisplay: settings.popoverDirectionDisplay,
            scale: scale,
            columns: displayColumns,
            scope: scope ?? mainTrafficScope,
            indent: indented ? 14 : 0,
            disclosureExpanded: disclosureExpanded,
            disclosureOnTrailingEdge: disclosureOnTrailingEdge,
            onToggleDisclosure: onToggleDisclosure
        )
        .overlay(alignment: .top) {
            if allowManualDrag && dropTargetID == usage.id {
                Rectangle()
                    .fill(NeManeemTheme.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            AppIdentityContextMenuContent(usage: usage, preferProcess: false)
            Divider()
            if expertFeaturesActive {
                Button(t("copyInformation")) { copyUsageInformation(usage, preferProcess: false) }
                Divider()
            }
            if settings.popoverVisibilityMode == .selectedOnly {
                if Set(settings.popoverSelectedProcessIDs).contains(usage.id) {
                    Button(t("removeFromSelection")) { settings.setProcessSelected(usage.id, selected: false, monitor: false) }
                } else {
                    Button(t("addToSelection")) { settings.setProcessSelected(usage.id, selected: true, monitor: false) }
                }
            } else if hidden {
                Button(t("showAppAgain")) { settings.setProcessHidden(usage.id, hidden: false, monitor: false) }
            } else {
                Button(t("hideApp")) { settings.setProcessHidden(usage.id, hidden: true, monitor: false) }
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
                    onMove: { source, target in
                        settings.moveManualProcess(source, before: target, monitor: false)
                    }
                ))
        }
        .transition(rowTransition)
    }

    @ViewBuilder
    private func appGroupRows(_ group: AppUsageGroup,
                              allowManualDrag: Bool,
                              hidden: Bool = false,
                              scope: TrafficValueScope? = nil) -> some View {
        let safariCompatibilityExpansion = settings.safariNetworkServiceGroupingEnabled && group.usage.isSafari && group.members.contains(where: isSafariNetworkServiceUsage)
        let canExpand = (expertFeaturesActive && group.isExpandable) || safariCompatibilityExpansion
        let expanded = canExpand && expandedAppIDs.contains(group.id)
        trafficRow(group.usage,
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
                               processMode: settings.popoverProcessDisplay,
                               unitMode: settings.popoverUnitMode,
                               directionDisplay: settings.popoverDirectionDisplay,
                               scale: scale,
                               columns: displayColumns,
                               scope: scope ?? mainTrafficScope,
                               indent: 22,
                               isProcessDetail: true,
                               allowsBlocking: false)
                    .contentShape(Rectangle())
                    .contextMenu {
                        AppIdentityContextMenuContent(usage: member, preferProcess: true)
                        Divider()
                        Button(t("copyInformation")) { copyUsageInformation(member, preferProcess: true) }
                        if expertProcessControlsEnabled {
                            Divider()
                            Button(t("hideProcessDetail")) { settings.setDetailProcessHidden(member.id, hidden: true) }
                        }
                    }
                Divider().padding(.leading, processDividerInset + 22)
            }
        }
    }

    private var activeFilteredUsages: [AppNetworkUsage] {
        let base: [AppNetworkUsage]
        if settings.popoverHideInactiveApps {
            let seconds = SettingsStore.normalizeInactiveHideDelay(settings.popoverInactiveHideDelaySeconds)
            base = displayedUsages.filter { usage in
                if usage.isActive { return true }
                return visibilityClock.timeIntervalSince(usage.lastActiveAt) <= seconds
            }
        } else {
            base = displayedUsages
        }
        return applyingManualParentMappings(base, mappings: settings.manualParentAppMappings)
    }

    private var selectedProcessIDs: Set<String> { Set(settings.popoverSelectedProcessIDs) }
    private var hiddenProcessIDs: Set<String> { Set(settings.popoverHiddenProcessIDs) }
    private var lowActivityWindowSeconds: TimeInterval {
        SettingsStore.normalizeLowActivityDuration(settings.popoverLowActivityDurationValue) * settings.popoverLowActivityDurationUnit.secondsMultiplier
    }

    private var lowActivityThresholdBytes: UInt64 {
        UInt64(SettingsStore.normalizeLowActivityData(settings.popoverLowActivityDataValue) * settings.popoverLowActivityDataUnit.byteMultiplier)
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
        guard settings.popoverVisibilityMode == .allApps else { return [] }
        return activeAppGroups.filter { appGroupMatchesHidden($0, hiddenIDs: hiddenProcessIDs) }
    }

    private var rawSystemUsages: [AppNetworkUsage] {
        guard settings.popoverGroupSystemProcesses else { return [] }
        return activeClassifiedUsages.systemServices.filter { usage in
            if settings.popoverVisibilityMode == .selectedOnly {
                return isAppUsageSelected(usage, selectedIDs: selectedProcessIDs)
            }
            return !hiddenProcessIDs.contains(usage.id)
        }
    }

    private var rawUngroupedSystemUsages: [AppNetworkUsage] {
        guard !settings.popoverGroupSystemProcesses else { return [] }
        return activeClassifiedUsages.systemServices.filter { usage in
            if settings.popoverVisibilityMode == .selectedOnly {
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
        guard settings.popoverVisibilityMode == .allApps, settings.popoverHideLowActivityApps else { return [] }
        return activeAppGroups.filter { group in
            if appGroupMatchesHidden(group, hiddenIDs: hiddenProcessIDs) { return false }
            return isLowActivity(group)
        }
    }

    private var unselectedAppGroups: [AppUsageGroup] {
        guard settings.popoverVisibilityMode == .selectedOnly, settings.popoverGroupUnselectedApps else { return [] }
        return activeAppGroups.filter { !appGroupMatchesSelection($0, selectedIDs: selectedProcessIDs) }
    }

    private var normalAppGroups: [AppUsageGroup] {
        let values: [AppUsageGroup]
        if settings.popoverVisibilityMode == .selectedOnly {
            values = activeAppGroups.filter { appGroupMatchesSelection($0, selectedIDs: selectedProcessIDs) }
        } else {
            values = activeAppGroups.filter { group in
                if appGroupMatchesHidden(group, hiddenIDs: hiddenProcessIDs) { return false }
                if settings.popoverHideLowActivityApps && isLowActivity(group) { return false }
                return true
            }
        }
        if settings.popoverSortMode == .currentUsage {
            let index = Dictionary(uniqueKeysWithValues: stableUsageOrder.enumerated().map { ($0.element, $0.offset) })
            return values.sorted {
                let li = index[$0.id] ?? Int.max
                let ri = index[$1.id] ?? Int.max
                if li == ri { return $0.usage.displayName.localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending }
                return li < ri
            }
        }
        let sorted = sortedTrafficUsages(values.map(\.usage), by: settings.popoverSortMode, manualOrder: settings.popoverManualOrder)
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
        guard settings.popoverSortMode == .manual else { return }
        settings.ensureManualOrderContains(appUsageGroups(activeFilteredUsages).map(\.id), monitor: false)
    }

    private var expertFeaturesActive: Bool {
        settings.expertFeaturesEnabled && settings.resourceMode != .austerity
    }

    private func copyUsageInformation(_ usage: AppNetworkUsage, preferProcess: Bool) {
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private var expertProcessControlsEnabled: Bool {
        expertFeaturesActive && settings.advancedProcessControlsEnabled
    }

    private var stateMessage: String? {
        if settings.resourceMode == .austerity { return t("austerityAppListPaused") }
        if firewall.monitoringPermissionRequestRecommended { return t("networkPermissionPending") }
        if traffic.hasPersistentConnectionError { return t("measurementEngineUnavailable") }
        if !traffic.hasCompletedInitialSample { return t("checkingActivity") }
        if visibleUsageIDs.isEmpty && !activeFilteredUsages.isEmpty { return t("noVisibleApps") }
        return visibleUsageIDs.isEmpty ? t("noActivity") : nil
    }

    private var rowTransition: AnyTransition {
        guard settings.popoverExitMotion && !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity))
    }

    private var removalAnimation: Animation? {
        guard settings.popoverExitMotion && !reduceMotion else { return .easeOut(duration: 0.12) }
        return .easeInOut(duration: 0.24)
    }

    private var processDividerInset: CGFloat {
        settings.popoverProcessDisplay == .nameOnly ? 14 : 46
    }

    private var dataLimitText: String {
        let total = recorder.currentCycleTotal.download + recorder.currentCycleTotal.upload
        let limit = settings.dataLimitBytes
        let value = settings.dataLimitDisplayMode == .used ? total : (limit > total ? limit - total : 0)
        return "\(SpeedFormatter.bytes(value)) / \(SpeedFormatter.bytes(limit))"
    }
}

func sortedTrafficUsages(_ values: [AppNetworkUsage], by mode: TrafficSortMode, manualOrder: [String]) -> [AppNetworkUsage] {
    let manualIndex = Dictionary(uniqueKeysWithValues: manualOrder.enumerated().map { ($1, $0) })
    return values.sorted { lhs, rhs in
        switch mode {
        case .currentUsage:
            if lhs.totalBytesPerSecond == rhs.totalBytesPerSecond {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.totalBytesPerSecond > rhs.totalBytesPerSecond
        case .download:
            if lhs.downloadBytesPerSecond == rhs.downloadBytesPerSecond { return lhs.displayName < rhs.displayName }
            return lhs.downloadBytesPerSecond > rhs.downloadBytesPerSecond
        case .upload:
            if lhs.uploadBytesPerSecond == rhs.uploadBytesPerSecond { return lhs.displayName < rhs.displayName }
            return lhs.uploadBytesPerSecond > rhs.uploadBytesPerSecond
        case .name:
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        case .manual:
            let li = manualIndex[lhs.id] ?? Int.max
            let ri = manualIndex[rhs.id] ?? Int.max
            if li == ri { return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending }
            return li < ri
        }
    }
}

struct TrafficTableHeader: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let processMode: ProcessDisplayMode
    let unitMode: SpeedUnitMode
    let directionDisplay: TransferDirectionDisplay
    let scale: CGFloat
    let columns: [StatusColumn]
    var expandProcessColumn: Bool = false

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(columns) { column in
                headerCell(column)
            }
        }
        .font(.system(size: 11.5 * scale, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, max(5, 6 * scale))
    }

    @ViewBuilder private func headerCell(_ column: StatusColumn) -> some View {
        switch column {
        case .process:
            HStack(spacing: 0) {
                Spacer().frame(width: processHeaderLeadingInset)
                Text(t("processName"))
                Spacer(minLength: 0)
            }
            .frame(minWidth: metrics.processWidth,
                   maxWidth: expandProcessColumn ? .infinity : metrics.processWidth,
                   alignment: .leading)
            .layoutPriority(expandProcessColumn ? 1 : 0)
        case .download:
            Text(directionTitle(.download)).lineLimit(1).minimumScaleFactor(0.72).frame(width: metrics.metricWidth, alignment: .trailing).help(t("download"))
        case .upload:
            Text(directionTitle(.upload)).lineLimit(1).minimumScaleFactor(0.72).frame(width: metrics.metricWidth, alignment: .trailing).help(t("upload"))
        case .today: usageHeader("today")
        case .week: usageHeader("thisWeek")
        case .month: usageHeader("thisMonth")
        case .session: usageHeader("session")
        case .dataCycle: usageHeader("dataCycle")
        case .allowed:
            Text(t("allowed")).frame(width: metrics.controlWidth, alignment: .center)
        }
    }

    private func usageHeader(_ key: String) -> some View {
        Text(t(key)).lineLimit(1).minimumScaleFactor(0.72).frame(width: metrics.usageWidth, alignment: .trailing)
    }

    private func directionTitle(_ direction: TrafficDirection) -> String {
        guard directionDisplay == .words else { return direction.shortSymbol }
        return t(direction == .download ? "download" : "upload")
    }

    // Keep the actual app rows exactly where they are. Only the one-word header
    // moves inward so it visually belongs to the app/name area instead of hugging
    // the disclosure edge.
    private var processHeaderLeadingInset: CGFloat {
        switch processMode {
        case .iconAndName: return 37 * scale
        case .iconOnly: return 18 * scale
        case .nameOnly: return 16 * scale
        }
    }

    private var metrics: StatusTableMetrics {
        statusTableMetrics(processMode: processMode,
                           unitMode: unitMode,
                           directionDisplay: directionDisplay,
                           scale: scale,
                           language: settings.language)
    }
}

struct AusterityPopoverView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @ObservedObject private var interface = AppEnvironment.shared.interfaceMonitor
    let openMainWindow: (MainWindowMode) -> Void

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "leaf")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(t("austerityAppListPaused"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(.horizontal, 18)

            if settings.popoverShowTotalSpeed {
                Divider()
                HStack(spacing: 10) {
                    Text(t("overall"))
                    Spacer()
                    Text("↓ " + SpeedFormatter.string(bytesPerSecond: interface.snapshot.downloadBytesPerSecond, mode: settings.popoverUnitMode))
                    Text("↑ " + SpeedFormatter.string(bytesPerSecond: interface.snapshot.uploadBytesPerSecond, mode: settings.popoverUnitMode))
                }
                .font(.system(size: 11.5).monospacedDigit())
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            if (settings.showDataLimitInPopover && settings.dataLimitEnabled) || settings.showSessionInPopover {
                Divider()
                CompactDataSessionArea(unitMode: settings.popoverUnitMode, horizontalPadding: 14)
            }

            Divider()
            HStack(spacing: 0) {
                Button { openMainWindow(.standard) } label: {
                    Image(systemName: "gearshape").frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(NMInlineActionButtonStyle())
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
                .help(t("settings"))

                Button(t("windowMode")) { openMainWindow(.monitor) }
                    .buttonStyle(NMInlineActionButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .foregroundStyle(.primary)

                Button(t("quit")) { NSApp.terminate(nil) }
                    .buttonStyle(NMInlineActionButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .help(t("quit"))
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .frame(width: 260)
        .tint(NeManeemTheme.accent)
    }

}

private struct CompactDataSessionArea: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController

    let unitMode: SpeedUnitMode
    let horizontalPadding: CGFloat

    @State private var showingSavedFeedback = false
    @State private var feedbackGeneration = 0

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if settings.showDataLimitInPopover && settings.dataLimitEnabled {
                HStack(spacing: 8) {
                    Text(t(settings.dataLimitDisplayMode == .used ? "used" : "remaining"))
                    Spacer()
                    Text(dataLimitText).monospacedDigit()
                }
                if firewall.isDataLimitInternetBlocked {
                    HStack(spacing: 8) {
                        Label(t("internetBlockedByLimit"), systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Button(t("continueUsingData")) { recorder.continueDataForCurrentCycle() }
                            .buttonStyle(NMInlineActionButtonStyle())
                    }
                }
            }

            if settings.showSessionInPopover {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 7) {
                        Text(t("session"))
                        Button { toggleSession() } label: {
                            Image(systemName: settings.sessionEnabled ? "stop.fill" : "play.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                                .frame(width: 13, height: 13)
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.recordingMode == .off || recorder.hasPendingSessionSchedule)
                        .help(t(settings.sessionEnabled ? "stopSession" : "startSession"))

                        if showingSavedFeedback {
                            Text(t("sessionSaved"))
                                .foregroundStyle(.secondary)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                        removal: .move(edge: .top).combined(with: .opacity)))
                        } else if recorder.hasPendingSessionSchedule {
                            Text(schedulePendingText)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(clockText(settings.sessionEnabled ? recorder.sessionElapsed : 0))
                                .monospacedDigit()
                            Text("·").foregroundStyle(.tertiary)
                            Text(SpeedFormatter.quantity(bytes: settings.sessionEnabled ? recorder.sessionTotal.download + recorder.sessionTotal.upload : 0,
                                                         mode: unitMode))
                                .monospacedDigit()
                            if settings.sessionEnabled && settings.sessionStartMode == .scheduled {
                                Text("· " + scheduledEndText)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .animation(.easeOut(duration: 0.18), value: showingSavedFeedback)
                }
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 6)
    }

    private func toggleSession() {
        if settings.sessionEnabled {
            if recorder.finishSession() != nil { showSavedFeedback() }
        } else {
            _ = recorder.startSession()
        }
    }

    private func showSavedFeedback() {
        feedbackGeneration += 1
        let generation = feedbackGeneration
        withAnimation(.easeOut(duration: 0.18)) { showingSavedFeedback = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard generation == feedbackGeneration else { return }
            withAnimation(.easeIn(duration: 0.18)) { showingSavedFeedback = false }
        }
    }

    private var dataLimitText: String {
        let used = recorder.currentCycleTotal.download + recorder.currentCycleTotal.upload
        let cap = settings.dataLimitBytes
        let value = settings.dataLimitDisplayMode == .used ? used : (cap > used ? cap - used : 0)
        return SpeedFormatter.bytes(value)
    }

    private var schedulePendingText: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(for: settings.language)
        formatter.setLocalizedDateFormatFromTemplate("Mdjm")
        return formatter.string(from: settings.scheduledSessionStartDate) + " " + t("scheduled")
    }

    private var scheduledEndText: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(for: settings.language)
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: settings.scheduledSessionEndDate) + " " + t("ends")
    }

    private func clockText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

struct TrafficSummaryRow: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder

    let title: String
    let download: UInt64
    let upload: UInt64
    let processMode: ProcessDisplayMode
    let unitMode: SpeedUnitMode
    let directionDisplay: TransferDirectionDisplay
    let scale: CGFloat
    let columns: [StatusColumn]
    var expandProcessColumn: Bool = false

    var body: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(columns) { column in
                summaryCell(column)
            }
        }
        .font(.system(size: 14 * scale, weight: .semibold))
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, max(8, 9 * scale))
    }

    @ViewBuilder private func summaryCell(_ column: StatusColumn) -> some View {
        switch column {
        case .process:
            HStack(spacing: 3 * scale) {
                // In the default icon+name presentation, align the Overall label
                // with the app-name text rather than the icon slot. Name-only mode
                // already starts at the leading edge; icon-only has no name anchor.
                if processMode == .iconAndName {
                    Color.clear.frame(width: 20 * scale, height: 1)
                }
                Text(title).lineLimit(1)
            }
            .frame(minWidth: metrics.processWidth,
                   maxWidth: expandProcessColumn ? .infinity : metrics.processWidth,
                   alignment: .leading)
            .layoutPriority(expandProcessColumn ? 1 : 0)
        case .download:
            metricCell(download)
        case .upload:
            metricCell(upload)
        case .today, .week, .month, .session, .dataCycle:
            let value = recorder.total(for: column)
            Text(SpeedFormatter.statusBytes(value.download &+ value.upload))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .monospacedDigit()
                .frame(width: metrics.usageWidth, alignment: .trailing)
        case .allowed:
            Color.clear.frame(width: metrics.controlWidth, height: 1)
        }
    }

    private func metricCell(_ value: UInt64) -> some View {
        Text(SpeedFormatter.string(bytesPerSecond: value, mode: unitMode))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .monospacedDigit()
            .frame(width: metrics.metricWidth, alignment: .trailing)
    }

    private var metrics: StatusTableMetrics {
        statusTableMetrics(processMode: processMode,
                           unitMode: unitMode,
                           directionDisplay: directionDisplay,
                           scale: scale,
                           language: settings.language)
    }
}

struct LiveTrafficRow: View {
    let usage: AppNetworkUsage
    let processMode: ProcessDisplayMode
    let unitMode: SpeedUnitMode
    let directionDisplay: TransferDirectionDisplay
    let scale: CGFloat
    let columns: [StatusColumn]
    var scope: TrafficValueScope = .all
    var indent: CGFloat = 0
    var disclosureExpanded: Bool? = nil
    var disclosureOnTrailingEdge: Bool = false
    var onToggleDisclosure: (() -> Void)? = nil
    var isProcessDetail: Bool = false
    var allowsBlocking: Bool = true
    var expandProcessColumn: Bool = false

    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(columns) { column in
                cell(column)
            }
        }
        .font(.system(size: 12.5 * scale))
        .foregroundStyle(usage.isActive ? .primary : .secondary)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(minHeight: 30 * scale)
    }

    @ViewBuilder private func cell(_ column: StatusColumn) -> some View {
        switch column {
        case .process:
            Group {
                if let disclosureExpanded, let onToggleDisclosure {
                    Button(action: onToggleDisclosure) {
                        processCellContent(disclosureExpanded: disclosureExpanded)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t("processDetails"))
                } else {
                    processCellContent(disclosureExpanded: nil)
                }
            }
            .frame(minWidth: metrics.processWidth,
                   maxWidth: expandProcessColumn ? .infinity : metrics.processWidth,
                   alignment: .leading)
            .layoutPriority(expandProcessColumn ? 1 : 0)
        case .download:
            speedCell(scopedDownload)
        case .upload:
            speedCell(scopedUpload)
        case .today, .week, .month, .session, .dataCycle:
            usageCell(column)
        case .allowed:
            Group {
                if allowsBlocking, usage.bundleIdentifier != nil {
                    Toggle("", isOn: Binding(
                        get: { firewall.isAllowed(usage.bundleIdentifier) },
                        set: { allowed in firewall.setAllowed(allowed, bundleIdentifier: usage.bundleIdentifier) }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .controlSize(scale > 1.15 ? .regular : .small)
                    .disabled(!firewall.isEnabled || firewall.isBusy)
                    .help(t("allowed"))
                } else { Text("—").foregroundStyle(.tertiary) }
            }
            .frame(width: metrics.controlWidth, alignment: .center)
        }
    }

    private func processCellContent(disclosureExpanded: Bool?) -> some View {
        HStack(spacing: 3 * scale) {
            if indent > 0 { Spacer().frame(width: indent) }
            if !disclosureOnTrailingEdge, let disclosureExpanded {
                Image(systemName: disclosureExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .frame(width: 11 * scale)
            }
            if processMode != .nameOnly {
                if isProcessDetail {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                        .frame(width: 20 * scale, height: 20 * scale)
                } else {
                    Image(nsImage: usage.icon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 20 * scale, height: 20 * scale).help(usage.displayName)
                }
            }
            if processMode != .iconOnly {
                Text(usage.displayName).lineLimit(1).truncationMode(.tail)
            }
            if disclosureOnTrailingEdge, let disclosureExpanded {
                Spacer(minLength: 2 * scale)
                Image(systemName: disclosureExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .frame(width: 11 * scale)
            }
        }
    }

    private func speedCell(_ value: UInt64) -> some View {
        Text(SpeedFormatter.string(bytesPerSecond: value, mode: unitMode))
            .lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
            .frame(width: metrics.metricWidth, alignment: .trailing)
    }

    @ViewBuilder private func usageCell(_ column: StatusColumn) -> some View {
        if settings.recordingMode != .perApp {
            Text("—").foregroundStyle(.tertiary)
                .frame(width: metrics.usageWidth, alignment: .trailing)
        } else if isProcessDetail {
            if let value = recorder.processTotals(for: column)[usage.id]?.bytes {
                Text(SpeedFormatter.statusBytes(value.totalBytes(for: scope)))
                    .lineLimit(1).minimumScaleFactor(0.78).monospacedDigit()
                    .frame(width: metrics.usageWidth, alignment: .trailing)
            } else {
                Text("—").foregroundStyle(.tertiary)
                    .frame(width: metrics.usageWidth, alignment: .trailing)
            }
        } else {
            Text(SpeedFormatter.statusBytes(appUsageTotal(for: column)))
                .lineLimit(1).minimumScaleFactor(0.78).monospacedDigit()
                .frame(width: metrics.usageWidth, alignment: .trailing)
        }
    }

    private func appUsageTotal(for column: StatusColumn) -> UInt64 {
        let identifier = usage.bundleIdentifier ?? usage.id
        let totals = recorder.appTotals(for: column)
        var value = totals[identifier] ?? AppBytePair()
        if settings.safariNetworkServiceGroupingEnabled,
           usage.isSafari,
           let legacyWebKit = totals["com.apple.WebKit.Networking"] {
            value.download &+= legacyWebKit.download
            value.upload &+= legacyWebKit.upload
            value.localDownload &+= legacyWebKit.localDownload
            value.localUpload &+= legacyWebKit.localUpload
            value.unknownDownload &+= legacyWebKit.unknownDownload
            value.unknownUpload &+= legacyWebKit.unknownUpload
        }
        return value.totalBytes(for: scope)
    }

    private var scopedDownload: UInt64 { usage.downloadBytesPerSecond(for: scope) }
    private var scopedUpload: UInt64 { usage.uploadBytesPerSecond(for: scope) }

    private var metrics: StatusTableMetrics {
        statusTableMetrics(processMode: processMode,
                           unitMode: unitMode,
                           directionDisplay: directionDisplay,
                           scale: scale,
                           language: settings.language)
    }
}

struct TrafficGroupRow: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    let title: String
    let count: Int
    let usages: [AppNetworkUsage]
    @Binding var isExpanded: Bool
    let processMode: ProcessDisplayMode
    let unitMode: SpeedUnitMode
    let directionDisplay: TransferDirectionDisplay
    let scale: CGFloat
    let columns: [StatusColumn]
    var scope: TrafficValueScope = .all
    var expandProcessColumn: Bool = false

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: metrics.spacing) {
                ForEach(columns) { column in groupCell(column) }
            }
            .font(.system(size: 12.5 * scale, weight: .medium))
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minHeight: 30 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private func groupCell(_ column: StatusColumn) -> some View {
        switch column {
        case .process:
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9 * scale, weight: .semibold)).frame(width: 12)
                Text(title).lineLimit(1)
                Text("\(count)").foregroundStyle(.tertiary)
            }
            .frame(minWidth: metrics.processWidth,
                   maxWidth: expandProcessColumn ? .infinity : metrics.processWidth,
                   alignment: .leading)
            .layoutPriority(expandProcessColumn ? 1 : 0)
        case .download:
            speedCell(usages.reduce(UInt64(0)) { $0 &+ $1.downloadBytesPerSecond(for: scope) })
        case .upload:
            speedCell(usages.reduce(UInt64(0)) { $0 &+ $1.uploadBytesPerSecond(for: scope) })
        case .today, .week, .month, .session, .dataCycle:
            if settings.recordingMode != .perApp {
                Text("—").foregroundStyle(.tertiary).frame(width: metrics.usageWidth, alignment: .trailing)
            } else {
                let map = recorder.appTotals(for: column)
                let total = usages.reduce(UInt64(0)) { result, usage in
                    let key = usage.bundleIdentifier ?? usage.id
                    var pair = map[key] ?? AppBytePair()
                    if settings.safariNetworkServiceGroupingEnabled && usage.isSafari, let legacyWebKit = map["com.apple.WebKit.Networking"] {
                        pair.download &+= legacyWebKit.download
                        pair.upload &+= legacyWebKit.upload
                        pair.localDownload &+= legacyWebKit.localDownload
                        pair.localUpload &+= legacyWebKit.localUpload
                        pair.unknownDownload &+= legacyWebKit.unknownDownload
                        pair.unknownUpload &+= legacyWebKit.unknownUpload
                    }
                    return result &+ pair.totalBytes(for: scope)
                }
                Text(SpeedFormatter.statusBytes(total)).lineLimit(1).minimumScaleFactor(0.78).monospacedDigit()
                    .frame(width: metrics.usageWidth, alignment: .trailing)
            }
        case .allowed:
            Text("—").foregroundStyle(.tertiary).frame(width: metrics.controlWidth, alignment: .center)
        }
    }

    private func speedCell(_ value: UInt64) -> some View {
        Text(SpeedFormatter.string(bytesPerSecond: value, mode: unitMode))
            .lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
            .frame(width: metrics.metricWidth, alignment: .trailing)
    }

    private var metrics: StatusTableMetrics {
        statusTableMetrics(processMode: processMode,
                           unitMode: unitMode,
                           directionDisplay: directionDisplay,
                           scale: scale,
                           language: settings.language)
    }
}

struct ManualTrafficOrderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    @Binding var dropTargetID: String?
    let onMove: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = draggingID, source != targetID else { return }
        dropTargetID = targetID
        onMove(source, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetID = nil
        draggingID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID { dropTargetID = nil }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
