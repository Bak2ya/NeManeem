import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MenuBarSettingsView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let highlight: String?
    @State private var advancedExpanded = false
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        Form {
            Section {
                MenuBarLayoutEditor(t: t)
            } header: {
                SettingsSectionHeader(t("menuBarLayout"), help: t("menuBarLayoutHelp"), helpLevel: .detail)
            }
            .modifier(SettingsHighlightBackground(active: highlight == "layout"))

            Section {
                RefreshIntervalEditor(title: t("networkSpeedRefreshInterval"), value: $settings.refreshIntervalSeconds, t: t)
            }
            .modifier(SettingsHighlightBackground(active: highlight == "refresh"))

            Section(t("displayAppearance")) {
                NMDisplaySizeControl(
                    title: t("displaySize"),
                    resetTitle: t("restoreDisplaySize"),
                    smallerHelp: t("sizeSmall"),
                    largerHelp: t("sizeLarge"),
                    value: $settings.menuFontSize,
                    range: 7...20,
                    step: 0.5,
                    defaultValue: SettingsStore.defaultMenuFontSize,
                    pointSize: { $0 }
                )
                NMValueChoice(t("unit"), selection: $settings.unitMode, options: [
                    (.compactBytes, t("unitCompact")),
                    (.bytesPerSecond, t("unitBytes")),
                    (.bitsPerSecond, t("unitBits"))
                ], equalSegmentWidths: true)
            }
            .modifier(SettingsHighlightBackground(active: highlight == "appearance"))

            Section {
                Button {
                    advancedExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(t("advanced"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if advancedExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsHelpText(t("warningAdvanced"))
                        HStack {
                            Text(t("font"))
                            Spacer()
                            Menu {
                                Button(t("systemDefaultFont")) { settings.menuFontFamily = "" }
                                Divider()
                                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                                    Button(family) { settings.menuFontFamily = family }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(settings.menuFontFamily.isEmpty ? t("systemDefaultFont") : settings.menuFontFamily).lineLimit(1)
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                            }
                            .menuIndicator(.hidden)
                            .frame(maxWidth: 220, alignment: .trailing)
                        }
                        NumericAdjuster(title: t("metricGap"), help: t("metricGapHelp"), value: $settings.metricGap, range: 0...20, step: 1, decimals: 0, suffix: "pt")
                        NumericAdjuster(title: t("rowSpacing"), help: t("rowSpacingHelp"), value: $settings.rowSpacing, range: 0...6, step: 0.5, decimals: 1, suffix: "pt")
                        HStack { Spacer(); Button(t("restore")) { settings.restoreAdvancedMenuDefaults() } }
                    }
                    .padding(.top, 6)
                }
            }
            .modifier(SettingsHighlightBackground(active: highlight == "advanced"))
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct MenuBarLayoutEditor: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let t: (String) -> String
    @State private var dragging: MenuBarElement?
    @State private var warningVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hidden: [MenuBarElement] { MenuBarElement.allCases.filter { !settings.menuBarElements.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Spacer()
                if warningVisible {
                    Text(t("atLeastOneMenuItem"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }

            row(title: t("topRow"), elements: settings.menuBarTopElements, top: true)
            row(title: t("bottomRow"), elements: settings.menuBarBottomElements, top: false)

            if !hidden.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("availableItems")).font(.caption).foregroundStyle(.secondary)
                    WrappingFlowLayout(spacing: 6) {
                        ForEach(hidden) { element in
                            chip(element, visible: false)
                                .onDrag { dragging = element; return NSItemProvider(object: element.rawValue as NSString) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func row(title: String, elements: [MenuBarElement], top: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(elements) { element in
                    chip(element, visible: true)
                        .onDrag { dragging = element; return NSItemProvider(object: element.rawValue as NSString) }
                        .onDrop(of: [UTType.text], delegate: MenuBarElementDropDelegate(target: element, top: top, dragging: $dragging, settings: settings))
                }
                Spacer(minLength: 20)
            }
            .frame(minHeight: 34)
            .padding(.horizontal, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                guard let element = dragging else { return false }
                settings.moveMenuBarElement(element, toTopRow: top)
                dragging = nil
                return true
            }
        }
    }

    private func chip(_ element: MenuBarElement, visible: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary)
            Text(label(element)).lineLimit(1)
            Button {
                if visible {
                    guard settings.menuBarElements.count > 1 else { showWarning(); return }
                    settings.setMenuBarElement(element, visible: false)
                } else {
                    settings.setMenuBarElement(element, visible: true)
                }
            } label: {
                Image(systemName: visible ? "xmark.circle.fill" : "plus.circle.fill").font(.caption)
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private func showWarning() {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { warningVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { warningVisible = false }
        }
    }

    private func label(_ element: MenuBarElement) -> String {
        switch element {
        case .uploadArrow: return "↑"
        case .uploadValue: return t("uploadValue")
        case .downloadArrow: return "↓"
        case .downloadValue: return t("downloadValue")
        case .limitValue: return t("limitValue")
        case .limitPercent: return t("limitPercent")
        case .limitLight: return t("limitLight")
        }
    }
}

private struct MenuBarElementDropDelegate: DropDelegate {
    let target: MenuBarElement
    let top: Bool
    @Binding var dragging: MenuBarElement?
    let settings: SettingsStore

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source != target else { return }
        settings.moveMenuBarElement(source, toTopRow: top, before: target)
    }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

// MARK: - Settings 2B. Interface / Popover and Monitor

private struct WrappingFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxWidth, usedWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct StatusColumnLayoutEditor: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let monitor: Bool
    let disabled: Bool
    let t: (String) -> String
    @State private var dragging: StatusColumn?

    private var visible: [StatusColumn] {
        monitor && !settings.monitorUsePopoverSettings ? settings.monitorColumns : settings.popoverColumns
    }
    private var hidden: [StatusColumn] { StatusColumn.allCases.filter { !visible.contains($0) } }
    private var directionDisplay: TransferDirectionDisplay {
        monitor && !settings.monitorUsePopoverSettings ? settings.monitorDirectionDisplay : settings.popoverDirectionDisplay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(t("columnLayout"))
                Spacer()
                Text(t("dragToReorder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visible) { column in
                        columnChip(column, visible: true)
                            .onDrag {
                                dragging = column
                                return NSItemProvider(object: column.rawValue as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: StatusColumnDropDelegate(
                                target: column,
                                monitor: monitor,
                                dragging: $dragging,
                                settings: settings
                            ))
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            if visible.contains(where: { [.today, .week, .month, .session, .dataCycle].contains($0) }) && settings.recordingMode != .perApp {
            }

            if !hidden.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("hiddenColumns"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    WrappingFlowLayout(spacing: 6) {
                        ForEach(hidden) { column in
                            columnChip(column, visible: false)
                                .onDrag {
                                    dragging = column
                                    return NSItemProvider(object: column.rawValue as NSString)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                        guard let column = dragging else { return false }
                        settings.setStatusColumnVisible(column, visible: false, monitor: monitor)
                        dragging = nil
                        return true
                    }
                }
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private func columnChip(_ column: StatusColumn, visible: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(title(column))
                .lineLimit(1)
            if column != .process {
                Button {
                    settings.setStatusColumnVisible(column, visible: !visible, monitor: monitor)
                } label: {
                    Image(systemName: visible ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .help(column == .process ? t("processColumnRequired") : "")
    }

    private func title(_ column: StatusColumn) -> String {
        switch column {
        case .process: return t("processName")
        case .download: return directionDisplay == .arrows ? "↓" : t("download")
        case .upload: return directionDisplay == .arrows ? "↑" : t("upload")
        case .today: return t("today")
        case .week: return t("thisWeek")
        case .month: return t("thisMonth")
        case .session: return t("session")
        case .dataCycle: return t("dataCycle")
        case .allowed: return t("allowed")
        }
    }
}

private struct StatusColumnDropDelegate: DropDelegate {
    let target: StatusColumn
    let monitor: Bool
    @Binding var dragging: StatusColumn?
    let settings: SettingsStore

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source != target else { return }
        if !(monitor && !settings.monitorUsePopoverSettings ? settings.monitorColumns : settings.popoverColumns).contains(source) {
            settings.setStatusColumnVisible(source, visible: true, monitor: monitor)
        }
        settings.moveStatusColumn(source, before: target, monitor: monitor)
    }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

enum InterfaceSurface { case popover, monitor }

struct PopoverSettingsView: View {
    @ObservedObject private var environment = AppEnvironment.shared
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var traffic = AppEnvironment.shared.appTrafficMonitor
    let surface: InterfaceSurface
    let highlight: String?
    @State private var advancedExpanded = false
    @State private var presetName = ""
    @State private var selectedPreset = ""
    private var monitor: Bool { surface == .monitor }
    private var inherited: Bool { monitor && settings.monitorUsePopoverSettings }
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        Form {
            if monitor {
                Section {
                    if inherited {
                        SettingsItemWithHelp(t("monitorFollowsPopoverHelp")) {
                            Toggle(t("monitorIndividualSettings"), isOn: monitorIndividualSettingsBinding)
                        }
                    } else {
                        Toggle(t("monitorIndividualSettings"), isOn: monitorIndividualSettingsBinding)
                    }
                }
                .modifier(SettingsHighlightBackground(active: highlight == "inherit"))
            }

            Section(t("displayContent")) {
                StatusColumnLayoutEditor(monitor: monitor, disabled: inherited, t: t)
                SettingsHelpText(t("columnFeatureVisibilityHelp"))
                SettingsItemWithHelp(t("showTotalSpeedHelp"), helpLevel: .detail) {
                    Toggle(t("showTotalSpeed"), isOn: showTotalSpeedBinding)
                }
                HStack(spacing: 14) {
                    Text(t("displayLocationLimit"))
                    Spacer()
                    Toggle(t("limit"), isOn: showLimitBinding).toggleStyle(.checkbox)
                    Toggle(t("session"), isOn: showSessionBinding).toggleStyle(.checkbox)
                }
            }
            .disabled(inherited)
            .opacity(inherited ? 0.55 : 1)
            .modifier(SettingsHighlightBackground(active: highlight == "content"))

            Section(t("displayAppearance")) {
                NMDisplaySizeControl(
                    title: t("displaySize"),
                    resetTitle: t("restoreDisplaySize"),
                    smallerHelp: t("sizeSmall"),
                    largerHelp: t("sizeLarge"),
                    value: scaleSliderBinding,
                    range: 0...3,
                    step: 1,
                    defaultValue: 1,
                    pointSize: { value in
                        Double(NSFont.systemFontSize * scaleForIndex(Int(value.rounded())).factor)
                    }
                )
                NMValueChoice(t("processDisplay"), selection: processDisplayBinding, options: [
                    (.iconOnly, t("iconOnly")), (.nameOnly, t("nameOnly")), (.iconAndName, t("iconAndName"))
                ], equalSegmentWidths: true)
                NMValueChoice(t("directionDisplay"), selection: directionDisplayBinding, options: [
                    (.words, t("directionWords")), (.arrows, t("directionArrows"))
                ])
                NMValueChoice(t("unit"), selection: unitBinding, options: [
                    (.compactBytes, t("unitCompact")), (.bytesPerSecond, t("unitBytes")), (.bitsPerSecond, t("unitBits"))
                ], equalSegmentWidths: true)
            }
            .disabled(inherited)
            .opacity(inherited ? 0.55 : 1)
            .modifier(SettingsHighlightBackground(active: highlight == "appearance"))

            Section {
                RefreshIntervalEditor(title: t("networkSpeedRefreshInterval"),
                                      value: refreshBinding,
                                      followsMenuBar: refreshFollowsMenuBarBinding,
                                      t: t)
                    .disabled(inherited)
                    .opacity(inherited ? 0.55 : 1)
            }
            .modifier(SettingsHighlightBackground(active: highlight == "refresh"))
            .disabled(inherited)
            .opacity(inherited ? 0.55 : 1)

            Section {
                Toggle(t("hideInactiveApps"), isOn: hideInactiveBinding)
                if hideInactiveBinding.wrappedValue {
                    ClosedDataRetentionEditor(title: t("inactiveHideDelay"), value: inactiveDelayBinding, t: t, zeroLabel: t("hideImmediately"), normalizer: SettingsStore.normalizeInactiveHideDelay)
                    SettingsHelpText(inactiveAppsDynamicHelp)
                    Toggle(t("disappearMotion"), isOn: exitMotionBinding)
                }
            } header: {
                SettingsSectionHeader(t("windowBehavior"))
            }
            .modifier(SettingsHighlightBackground(active: highlight == "window"))
            .disabled(inherited)
            .opacity(inherited ? 0.55 : 1)

            Section {
                Button {
                    advancedExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(t("advanced"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if advancedExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        NMValueChoice(t("appVisibility"), selection: visibilityBinding, options: [
                            (.allApps, t("allApps")), (.selectedOnly, t("selectedAppsOnly"))
                        ])
                        if visibilityBinding.wrappedValue == .selectedOnly {
                            ObservedAppSelectionEditor(usages: traffic.observedUsages, selectedIDs: selectedIDsBinding, t: t)
                            Toggle(t("groupUnselectedApps"), isOn: groupUnselectedBinding)
                        } else {
                            Toggle(t("hideLowActivityApps"), isOn: hideLowActivityBinding)
                            if hideLowActivityBinding.wrappedValue {
                                LowActivityThresholdEditor(title: t("lowActivityThreshold"),
                                                           durationValue: lowActivityDurationValueBinding,
                                                           durationUnit: lowActivityDurationUnitBinding,
                                                           dataValue: lowActivityDataValueBinding,
                                                           dataUnit: lowActivityDataUnitBinding,
                                                           t: t)
                                SettingsHelpText(lowActivityAppsDynamicHelp)
                            }
                        }
                        Toggle(t("groupSystemProcesses"), isOn: groupSystemBinding)
                        Picker(t("sortBy"), selection: sortBinding) { sortOptions }.pickerStyle(.menu).nmNeutralValueControl()
                        if sortBinding.wrappedValue == .manual {
                            SettingsHelpText(t("manualSortHelp"), level: .detail)
                            ManualOrderSettingsEditor(usages: appUsageGroups(traffic.usages).map(\.usage), monitor: monitor)
                            presetControls
                        }
                        if !monitor {
                            ClosedDataRetentionEditor(title: t("closedDataRetention"), value: retentionBinding, t: t)
                        }
                        if settings.expertFeaturesEnabled {
                            SettingsItemWithHelp(t("advancedProcessControlsHelp")) {
                                Toggle(t("advancedProcessControls"), isOn: $settings.advancedProcessControlsEnabled)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .disabled(inherited)
            .opacity(inherited ? 0.55 : 1)
            .modifier(SettingsHighlightBackground(active: highlight == "advanced"))
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            traffic.hydrateObservedCatalogAfterLaunch()
            traffic.enrichObservedCatalogMetadataIncrementally()
            traffic.setDemand(.settingsStatusWindow, active: true)
        }
        .onDisappear { traffic.setDemand(.settingsStatusWindow, active: false) }
    }

    private var monitorIndividualSettingsBinding: Binding<Bool> {
        Binding(get: { !settings.monitorUsePopoverSettings }, set: { enabled in
            if enabled { settings.copyPopoverSettingsToMonitor(); settings.monitorUsePopoverSettings = false }
            else { settings.monitorUsePopoverSettings = true }
        })
    }
    private var scaleSliderBinding: Binding<Double> {
        Binding(get: { Double(scaleIndex(scaleBinding.wrappedValue)) }, set: { value in scaleBinding.wrappedValue = scaleForIndex(Int(value.rounded())) })
    }
    private func scaleIndex(_ value: PopoverScale) -> Int { [.small,.standard,.large,.extraLarge].firstIndex(of: value) ?? 1 }
    private func scaleForIndex(_ index: Int) -> PopoverScale { [.small,.standard,.large,.extraLarge][min(3,max(0,index))] }
    private var usesMonitorOverrides: Bool { monitor && !settings.monitorUsePopoverSettings }
    private var scaleBinding: Binding<PopoverScale> { usesMonitorOverrides ? $settings.monitorScale : $settings.popoverScale }
    private var processDisplayBinding: Binding<ProcessDisplayMode> { usesMonitorOverrides ? $settings.monitorProcessDisplay : $settings.popoverProcessDisplay }
    private var directionDisplayBinding: Binding<TransferDirectionDisplay> { usesMonitorOverrides ? $settings.monitorDirectionDisplay : $settings.popoverDirectionDisplay }
    private var unitBinding: Binding<SpeedUnitMode> { usesMonitorOverrides ? $settings.monitorUnitMode : $settings.popoverUnitMode }
    private var visibilityBinding: Binding<AppVisibilityMode> { usesMonitorOverrides ? $settings.monitorVisibilityMode : $settings.popoverVisibilityMode }
    private var selectedIDsBinding: Binding<[String]> { usesMonitorOverrides ? $settings.monitorSelectedProcessIDs : $settings.popoverSelectedProcessIDs }
    private var groupUnselectedBinding: Binding<Bool> { usesMonitorOverrides ? $settings.monitorGroupUnselectedApps : $settings.popoverGroupUnselectedApps }
    private var hideLowActivityBinding: Binding<Bool> { usesMonitorOverrides ? $settings.monitorHideLowActivityApps : $settings.popoverHideLowActivityApps }
    private var lowActivityDurationValueBinding: Binding<Double> { usesMonitorOverrides ? $settings.monitorLowActivityDurationValue : $settings.popoverLowActivityDurationValue }
    private var lowActivityDurationUnitBinding: Binding<LowActivityDurationUnit> { usesMonitorOverrides ? $settings.monitorLowActivityDurationUnit : $settings.popoverLowActivityDurationUnit }
    private var lowActivityDataValueBinding: Binding<Double> { usesMonitorOverrides ? $settings.monitorLowActivityDataValue : $settings.popoverLowActivityDataValue }
    private var lowActivityDataUnitBinding: Binding<LowActivityDataUnit> { usesMonitorOverrides ? $settings.monitorLowActivityDataUnit : $settings.popoverLowActivityDataUnit }

    private var inactiveAppsDynamicHelp: String {
        String(format: t("inactiveAppsDynamicHelp"), shortDuration(inactiveDelayBinding.wrappedValue, unit: t("seconds")))
    }

    private var lowActivityAppsDynamicHelp: String {
        let durationUnit = lowActivityDurationUnitBinding.wrappedValue == .hours ? t("hours") : t("minutes")
        let duration = shortDuration(lowActivityDurationValueBinding.wrappedValue, unit: durationUnit)
        let amount = shortDuration(lowActivityDataValueBinding.wrappedValue,
                                   unit: lowActivityDataUnitBinding.wrappedValue.rawValue)
        return String(format: t("lowActivityAppsDynamicHelp"), duration, amount)
    }

    private func shortDuration(_ value: Double, unit: String) -> String {
        let number: String
        if abs(value.rounded() - value) < 0.001 { number = String(Int(value.rounded())) }
        else { number = String(format: "%.1f", value) }
        return "\(number)\(unit)"
    }
    private var groupSystemBinding: Binding<Bool> { usesMonitorOverrides ? $settings.monitorGroupSystemProcesses : $settings.popoverGroupSystemProcesses }
    private var sortBinding: Binding<TrafficSortMode> { usesMonitorOverrides ? $settings.monitorSortMode : $settings.popoverSortMode }
    private var retentionBinding: Binding<Double> { $settings.popoverClosedDataRetentionSeconds }
    private var showTotalSpeedBinding: Binding<Bool> { usesMonitorOverrides ? $settings.monitorShowTotalSpeed : $settings.popoverShowTotalSpeed }
    private var hideInactiveBinding: Binding<Bool> { usesMonitorOverrides ? $settings.monitorHideInactiveApps : $settings.popoverHideInactiveApps }
    private var inactiveDelayBinding: Binding<Double> { usesMonitorOverrides ? $settings.monitorInactiveHideDelaySeconds : $settings.popoverInactiveHideDelaySeconds }
    private var exitMotionBinding: Binding<Bool> { usesMonitorOverrides ? $settings.monitorExitMotion : $settings.popoverExitMotion }
    private var refreshFollowsMenuBarBinding: Binding<Bool>? {
        if monitor {
            return usesMonitorOverrides ? $settings.monitorUseMenuBarRefresh : nil
        }
        return $settings.popoverUseMenuBarRefresh
    }
    private var refreshBinding: Binding<Double> {
        if usesMonitorOverrides { return $settings.monitorRefreshIntervalSeconds }
        return Binding(get: { settings.effectivePopoverRefreshIntervalSeconds }, set: { if !settings.popoverUseMenuBarRefresh { settings.popoverRefreshIntervalSeconds = $0 } })
    }
    private var showLimitBinding: Binding<Bool> {
        if monitor { return $settings.showDataLimitInMonitor }
        return $settings.showDataLimitInPopover
    }
    private var showSessionBinding: Binding<Bool> {
        // Session remains a shared summary feature while monitor inherits Popover by default.
        $settings.showSessionInPopover
    }

    @ViewBuilder private var presetControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField(t("presetName"), text: $presetName)
                Button(t("savePreset")) {
                    let order = monitor ? settings.monitorManualOrder : settings.popoverManualOrder
                    settings.saveTrafficOrderPreset(name: presetName, order: order)
                    presetName = ""
                }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !settings.trafficOrderPresets.isEmpty {
                HStack {
                    Picker(t("orderPreset"), selection: $selectedPreset) {
                        Text(t("choosePreset")).tag("")
                        ForEach(settings.trafficOrderPresets) { preset in Text(preset.name).tag(preset.id) }
                    }
                    .pickerStyle(.menu)
                .nmNeutralValueControl()
                    .onChange(of: selectedPreset) { value in if !value.isEmpty { settings.applyTrafficOrderPreset(id: value, monitor: monitor) } }
                    Button(t("deletePreset")) {
                        guard !selectedPreset.isEmpty else { return }
                        settings.deleteTrafficOrderPreset(id: selectedPreset); selectedPreset = ""
                    }
                    .disabled(selectedPreset.isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var sortOptions: some View {
        Text(t("sortCurrentUsage")).tag(TrafficSortMode.currentUsage)
        Text(t("download")).tag(TrafficSortMode.download)
        Text(t("upload")).tag(TrafficSortMode.upload)
        Text(t("processName")).tag(TrafficSortMode.name)
        Text(t("sortManual")).tag(TrafficSortMode.manual)
    }
}

private struct ManualOrderSettingsEditor: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let usages: [AppNetworkUsage]
    let monitor: Bool
    @State private var draggingID: String?
    @State private var dropTargetID: String?

    private var orderedUsages: [AppNetworkUsage] {
        let order = monitor && !settings.monitorUsePopoverSettings ? settings.monitorManualOrder : settings.popoverManualOrder
        return sortedTrafficUsages(usages, by: .manual, manualOrder: order)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(orderedUsages.prefix(12)) { usage in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                    Image(nsImage: usage.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                    Text(usage.displayName)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
                .overlay(alignment: .top) {
                    if dropTargetID == usage.id {
                        Rectangle().fill(NeManeemTheme.accent).frame(height: 2)
                    }
                }
                .onDrag {
                    draggingID = usage.id
                    return NSItemProvider(object: usage.id as NSString)
                }
                .onDrop(of: [UTType.text], delegate: ManualTrafficOrderDropDelegate(
                    targetID: usage.id,
                    draggingID: $draggingID,
                    dropTargetID: $dropTargetID,
                    onMove: { source, target in settings.moveManualProcess(source, before: target, monitor: monitor) }
                ))
                Divider()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .onAppear { settings.ensureManualOrderContains(usages.map(\.id), monitor: monitor) }
        .onChange(of: usages.map(\.id)) { ids in settings.ensureManualOrderContains(ids, monitor: monitor) }
    }
}

// MARK: - Settings 3. Network


