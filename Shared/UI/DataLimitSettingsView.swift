import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum WarningRepeatPreset: String, CaseIterable, Identifiable {
    case once
    case min30
    case hour1
    case custom
    var id: String { rawValue }
}

private enum WarningThresholdUnit: String, CaseIterable, Identifiable {
    case percentage = "%"
    case terabytes = "TB"
    case gigabytes = "GB"
    case megabytes = "MB"
    var id: String { rawValue }

    var dataLimitUnit: DataLimitUnit? {
        switch self {
        case .percentage: return nil
        case .terabytes: return .terabytes
        case .gigabytes: return .gigabytes
        case .megabytes: return .megabytes
        }
    }
}

private enum LimitEndChoice: String, CaseIterable, Identifiable {
    case fromStart, selectedMonthEnd, endDate
    var id: String { rawValue }
}

struct DataLimitSettingsView: View {
    @ObservedObject private var environment = AppEnvironment.shared
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @ObservedObject private var interface = AppEnvironment.shared.interfaceMonitor
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled

    @State private var balanceMode: DataLimitDisplayMode = .used
    @State private var balanceValue: Double = 0
    @State private var balanceUnit: DataLimitUnit = .gigabytes
    @State private var warningRepeatPreset: WarningRepeatPreset = .once
    @State private var customRepeatMinutes = 90
    @State private var warningRepeatCustomText = "90"
    @State private var editingWarningRepeatCustom = false
    @State private var invalidWarningRepeatCustom = false
    @FocusState private var warningRepeatCustomFocused: Bool
    @State private var directNetworkName = ""
    @State private var showingNetworkChooser = false
    @State private var showingClearDataUsageRecordsConfirm = false
    @State private var usageRecordingEnabledHere = false
    let highlight: String?

    init(highlight: String? = nil) { self.highlight = highlight }

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }
    private var calendar: Calendar { Calendar.current }
    private var isDataLimitPrerequisiteSatisfied: Bool { settings.recordingMode != .off }
    private var limitRecordingStatus: String {
        isDataLimitPrerequisiteSatisfied ? t("usageRecordingOn") : t("usageRecordingOff")
    }

    var body: some View {
        VStack(spacing: 0) {

            Form {
                if !isDataLimitPrerequisiteSatisfied {
                    Section(t("usageSettingsRequired")) {
                        SettingsHelpText(t("limitNeedsRecording"))
                        HStack {
                            Text(t("usageRecording"))
                            Spacer()
                            Text(limitRecordingStatus)
                                .foregroundStyle(.secondary)
                            Button(t("enableUsageRecording")) {
                                settings.recordingMode = .perApp
                                usageRecordingEnabledHere = true
                            }
                            .buttonStyle(NMNeutralActionButtonStyle())
                        }
                    }
                } else if usageRecordingEnabledHere {
                    Section {
                        Text(t("usageRecordingEnabledConfirmation"))
                            .fontWeight(.semibold)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Text(t("usageRecordingSettingsHintPrefix"))
                                Label(t("usageSettingsTab"), systemImage: MainSection.usage.icon)
                                    .fontWeight(.medium)
                                Text(t("usageRecordingSettingsHintSuffix"))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t("usageRecordingSettingsHintPrefix"))
                                HStack(spacing: 4) {
                                    Label(t("usageSettingsTab"), systemImage: MainSection.usage.icon)
                                        .fontWeight(.medium)
                                    Text(t("usageRecordingSettingsHintSuffix"))
                                }
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle(isOn: $settings.dataLimitEnabled) {
                        Text(t("dataLimitSettings")).fontWeight(.semibold)
                    }
                    .disabled(!isDataLimitPrerequisiteSatisfied)
                    if !settings.dataLimitEnabled && isDataLimitPrerequisiteSatisfied {
                        SettingsHelpText(t("dataLimitDisabledHelp"))
                    }
                }
                .modifier(SettingsHighlightBackground(active: highlight == "limit"))

                if settings.dataLimitEnabled && isDataLimitPrerequisiteSatisfied {
                    Section {
                        HStack {
                            Text(t("limit"))
                            Spacer()
                            TextField("", value: $settings.dataLimitValue, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 72, idealWidth: 82, maxWidth: 96)
                                .nmSelectAllOnEdit()
                            Picker(t("unit"), selection: $settings.dataLimitUnit) {
                                ForEach(DataLimitUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                .nmNeutralValueControl().frame(minWidth: 78, idealWidth: 88)
                        }

                        HStack {
                            Text(t("currentShort"))
                            Spacer()
                            TextField("", value: $balanceValue, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 72, idealWidth: 82, maxWidth: 96)
                                .nmSelectAllOnEdit()
                            Picker("", selection: $balanceUnit) {
                                ForEach(DataLimitUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                .nmNeutralValueControl().frame(minWidth: 78)
                            Picker("", selection: $balanceMode) {
                                Text(t("usedShort")).tag(DataLimitDisplayMode.used)
                                Text(t("remainingShort")).tag(DataLimitDisplayMode.remaining)
                            }
                            .labelsHidden().pickerStyle(.menu)
                .nmNeutralValueControl().frame(minWidth: 108, idealWidth: 116)
                            Button(t("apply")) { applyCurrentPlanState() }
                                .buttonStyle(NMPrimaryActionButtonStyle())
                        }
                        .modifier(SettingsHighlightBackground(active: highlight == "current"))

                        HStack {
                            Text(t("remainingLimit"))
                            Spacer()
                            Text(remainingLimitText)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(settings.dataLimitEnabled ? Color.primary : Color(nsColor: .disabledControlTextColor))

                        HStack(spacing: 14) {
                            Text(t("displayLocation"))
                            Spacer()
                            Toggle(t("popover"), isOn: $settings.showDataLimitInPopover).toggleStyle(.checkbox)
                            Toggle(t("monitorWindow"), isOn: $settings.showDataLimitInMonitor).toggleStyle(.checkbox)
                            Toggle(t("menubar"), isOn: menuBarLimitBinding).toggleStyle(.checkbox)
                        }
                        NMValueChoice(t("displayMode"), selection: $settings.dataLimitDisplayMode, options: [
                            (.used, t("usageAmount")), (.remaining, t("remainingAmount"))
                        ])
                    } header: {
                        SettingsSectionHeader(t("limitBasicSettingsSection"), help: t("limitCountsBothDirectionsHelp"), detailHelp: t("dataLimitHelp"))
                    }
                    .disabled(!isDataLimitPrerequisiteSatisfied)

                    Section(t("limitApplicationSection")) {
                        targetNetworkEditor
                        if settings.separateLocalTraffic {
                            if settings.dataLimitTrafficScope == .internetOnly {
                                SettingsItemWithHelp(t("internetOnlyUsageEssential"), detailHelp: t("internetOnlyUsageDetail")) {
                                    NMValueChoice(t("consumptionBasis"), selection: $settings.dataLimitTrafficScope, options: [
                                        (.internetOnly, t("internetOnly")), (.allTraffic, t("allTraffic"))
                                    ])
                                }
                            } else {
                                SettingsItemWithHelp(t("allUsageBasisHelp")) {
                                    NMValueChoice(t("consumptionBasis"), selection: $settings.dataLimitTrafficScope, options: [
                                        (.internetOnly, t("internetOnly")), (.allTraffic, t("allTraffic"))
                                    ])
                                }
                            }
                        } else {
                            SettingsItemWithHelp(t("localSeparationNeededForInternetOnly")) {
                                HStack(spacing: 10) {
                                    Text(t("consumptionBasis"))
                                    Spacer()
                                    Text(t("allTraffic")).foregroundStyle(.secondary)
                                    Button(t("turnOn")) {
                                        environment.requestSettingsSection?("network-local")
                                    }
                                    .buttonStyle(NMNeutralActionButtonStyle())
                                }
                            }
                        }
                    }
                    .modifier(SettingsHighlightBackground(active: highlight == "application"))
                    .disabled(!isDataLimitPrerequisiteSatisfied)

                    Section(t("limitManagementPeriodSection")) {
                        managementPeriodEditor
                    }
                    .modifier(SettingsHighlightBackground(active: highlight == "period"))
                    .disabled(!isDataLimitPrerequisiteSatisfied)

                    Section(t("limitAlertsAndActionSection")) {
                        Toggle(t("dataLimitWarning"), isOn: $settings.dataLimitWarningEnabled)
                        .fontWeight(.semibold)
                        .onChange(of: settings.dataLimitWarningEnabled) { enabled in
                            guard enabled else { return }
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }

                    if settings.dataLimitWarningEnabled {
                        Toggle(t("warningLightLink"), isOn: $settings.dataLimitWarningLightLinked)
                            .onChange(of: settings.dataLimitWarningLightLinked) { linked in
                                if linked { ensureWarningLightRuleSelections() }
                            }
                        if settings.dataLimitWarningLightLinked, !settings.dataLimitWarningRules.isEmpty {
                            warningLightPickerRow("🟡", color: .yellow, selection: warningLightYellowRuleBinding, options: warningLightRuleOptions(for: .yellow))
                            warningLightPickerRow("🟠", color: .orange, selection: warningLightOrangeRuleBinding, options: warningLightRuleOptions(for: .orange))
                            warningLightPickerRow("🔴", color: .red, selection: warningLightRedRuleBinding, options: warningLightRuleOptions(for: .red))
                        }

                        ForEach(Array(settings.dataLimitWarningRules.enumerated()), id: \.element.id) { index, rule in
                            warningRuleEditor(ruleID: rule.id, displayIndex: index, fallback: rule)
                        }
                        HStack {
                            Button { addWarningRule() } label: { Label(t("addWarning"), systemImage: "plus") }
                                .disabled(settings.dataLimitWarningRules.count >= SettingsStore.maximumDataLimitWarningRules)
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            warningRepeatEditor
                            SettingsHelpText(t("notificationStyleSystemHelp"))
                        }
                    }
                    if settings.dataLimitReachedAction == .blockInternet {
                        SettingsItemWithHelp(t("blockDataHelp")) {
                            NMValueChoice(t("limitReachedAction"), selection: $settings.dataLimitReachedAction, options: [
                                (.continueData, t("continueData")),
                                (.blockInternet, t("blockData"))
                            ])
                        }
                        .disabled(!isDataLimitPrerequisiteSatisfied)
                    } else {
                        NMValueChoice(t("limitReachedAction"), selection: $settings.dataLimitReachedAction, options: [
                            (.continueData, t("continueData")),
                            (.blockInternet, t("blockData"))
                        ])
                        .disabled(!isDataLimitPrerequisiteSatisfied)
                    }

                    if firewall.isDataLimitInternetBlocked {
                        HStack {
                            Label(t("internetBlockedByLimit"), systemImage: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                            Spacer()
                            Button(t("continueUsingData")) { recorder.continueDataForCurrentCycle() }
                        }
                    }
                    }
                    .disabled(!isDataLimitPrerequisiteSatisfied)
                }

                Section {
                    if displayedDataUsageRecords.isEmpty {
                        SettingsHelpText(t("noDataUsageRecords"))
                    } else {
                        HStack(spacing: 18) {
                            metric(t("recentAverage"), recordAverage)
                            metric(t("recentMaximum"), recordMaximum)
                            metric(t("recentMinimum"), recordMinimum)
                            Spacer(minLength: 8)
                            Menu {
                                Button("\(t("exportAllRecords")) · \(t("excelFormat"))") {
                                    exportDataUsageRecords(exportableDataUsageRecords, format: .xlsx)
                                }
                                Button("\(t("exportAllRecords")) · \(t("csvFormat"))") {
                                    exportDataUsageRecords(exportableDataUsageRecords, format: .csv)
                                }
                                Divider()
                                Button(t("deleteAllHistory"), role: .destructive) { showingClearDataUsageRecordsConfirm = true }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                        }
                        ForEach(displayedDataUsageRecords.prefix(6)) { record in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(recordRange(record))
                                        if let label = record.label, !label.isEmpty {
                                            Text(label)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(.quaternary, in: Capsule())
                                        }
                                    }
                                    if let network = record.networkDisplayName, !network.isEmpty {
                                        Text(network).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(SpeedFormatter.bytes(record.total)).monospacedDigit()
                                if record.limitBytes > 0 {
                                    Text("/ \(SpeedFormatter.bytes(record.limitBytes))").foregroundStyle(.secondary).monospacedDigit()
                                    Text(String(format: "%.0f%%", (Double(record.total) / Double(record.limitBytes)) * 100)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                Menu {
                                    Button(t("excelFormat")) { exportDataUsageRecords([record], format: .xlsx) }
                                    Button(t("csvFormat")) { exportDataUsageRecords([record], format: .csv) }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .menuStyle(.borderlessButton)
                                .help(t("exportSelectedRecord"))

                                Button {
                                    deleteDataUsageRecord(record)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(NMDestructiveIconButtonStyle())
                                .help(t("deleteRecord"))
                            }
                            .font(.callout)
                        }
                    }
                } header: {
                    SettingsSectionHeader(t("dataUsageRecords"), help: t("dataUsageRecordsHelp"))
                }
            }
            .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showingNetworkChooser) { networkChooserSheet }
        .confirmationDialog(t("deleteAllHistory"), isPresented: $showingClearDataUsageRecordsConfirm, titleVisibility: .visible) {
            Button(t("deleteAllHistory"), role: .destructive) { clearAllDataUsageRecords() }
            Button(t("cancel"), role: .cancel) {}
        } message: {
            Text(t("deleteAllDataUsageRecordsConfirm"))
        }
        .onAppear {
            syncWarningRepeatPreset()
            normalizeWarningRuleOrder()
            if settings.dataLimitWarningLightLinked { ensureWarningLightRuleSelections() }
            interface.refreshWiFiIdentityAuthorizationStatus()
            interface.refreshWiFiNetworkChoices(scanNearby: false)
            if settings.dataLimitEndDate <= settings.dataLimitStartDate {
                settings.dataLimitEndDate = calendar.date(byAdding: .month, value: 1, to: settings.dataLimitStartDate) ?? settings.dataLimitStartDate.addingTimeInterval(30 * 86400)
            }
        }
        .onDisappear { usageRecordingEnabledHere = false }
        .onChange(of: interface.snapshot.networkIdentifier) { newIdentifier in migrateSelectedNetworkIdentityIfNeeded(newIdentifier) }
        .onChange(of: settings.dataLimitStartDate) { date in
            settings.dataLimitSelectedEndMonth = calendar.component(.month, from: date)
            settings.dataLimitMonthlyStartDay = calendar.component(.day, from: date)
        }
        .onChange(of: warningRepeatCustomFocused) { focused in
            if focused { nmSelectAllCurrentTextEditor() }
        }
    }

    private var menuBarLimitBinding: Binding<Bool> {
        Binding(get: { settings.menuBarHasLimitElement }, set: { settings.setDataLimitVisibleInMenuBar($0) })
    }

    private var warningRepeatLabels: [String] {
        [t("onceOnly"), t("every30Minutes"), t("everyHour"), t("custom")]
    }

    private var warningRepeatCustomDisplayLabel: String {
        warningRepeatPreset == .custom ? "\(customRepeatMinutes) \(t("minutes"))" : t("custom")
    }

    private var warningRepeatCustomSlotWidth: CGFloat {
        // External geometry is fixed before/during/after editing. A committed
        // custom value may change its text, but it must not resize the segment.
        fixedCustomInputSlotWidth(label: t("custom"), inputSample: "9999", trailingText: t("minutes"))
    }

    private var warningRepeatSegmentWidth: CGFloat {
        max(warningRepeatLabels.dropLast().map(compactSegmentNaturalWidth).max() ?? 52,
            warningRepeatCustomSlotWidth)
    }

    private var warningRepeatSegmentWidths: [CGFloat] {
        Array(repeating: warningRepeatSegmentWidth, count: warningRepeatLabels.count)
    }

    private var warningRepeatControlWidth: CGFloat {
        4 + CGFloat(max(0, warningRepeatLabels.count - 1))
            + warningRepeatSegmentWidth * CGFloat(warningRepeatLabels.count)
    }

    private var warningRepeatEditor: some View {
        HStack(spacing: 10) {
            Text(t("repeatWarning"))
            Spacer(minLength: 10)
            warningRepeatControl
        }
    }

    private var warningRepeatControl: some View {
        HStack(spacing: 1) {
            warningRepeatChoice(t("onceOnly"), preset: .once)
                .frame(width: warningRepeatSegmentWidths[0])
            warningRepeatChoice(t("every30Minutes"), preset: .min30)
                .frame(width: warningRepeatSegmentWidths[1])
            warningRepeatChoice(t("everyHour"), preset: .hour1)
                .frame(width: warningRepeatSegmentWidths[2])
            Group {
                if editingWarningRepeatCustom {
                    let unit = t("minutes")
                    let fieldWidth = customInputTextFieldWidth(slotWidth: warningRepeatSegmentWidth, trailingText: unit)
                    NMInlineCustomNumericEditor(
                        text: $warningRepeatCustomText,
                        unit: unit,
                        fieldWidth: fieldWidth,
                        confirmationAccessibilityLabel: t("apply"),
                        onCommit: commitWarningRepeatCustom,
                        onCancel: cancelWarningRepeatCustomEdit,
                        onEdit: { invalidWarningRepeatCustom = false }
                    )
                    .frame(height: settingsCompactSegmentContentHeight)
                    .padding(.leading, settingsCustomInputHorizontalPadding)
                    .padding(.trailing, settingsCustomInputConfirmationTrailingPadding)
                    .frame(width: warningRepeatSegmentWidth, height: settingsCompactSegmentContentHeight, alignment: .center)
                    .background(invalidWarningRepeatCustom ? Color.red.opacity(0.08) : NMValueChoiceAppearance.editingBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(invalidWarningRepeatCustom ? Color.red.opacity(0.9) : NMValueChoiceAppearance.editingBorder, lineWidth: invalidWarningRepeatCustom ? 1.2 : 0.8)
                    }
                    .onExitCommand(perform: cancelWarningRepeatCustomEdit)
                } else {
                    warningRepeatChoice(warningRepeatCustomDisplayLabel, preset: .custom)
                }
            }
            .frame(width: warningRepeatSegmentWidths[3])
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.6) }
        .frame(width: warningRepeatControlWidth)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func warningRepeatChoice(_ label: String, preset: WarningRepeatPreset) -> some View {
        let selected = warningRepeatPreset == preset && !editingWarningRepeatCustom
        return Button {
            if preset == .custom {
                beginWarningRepeatCustomEdit()
            } else {
                editingWarningRepeatCustom = false
                invalidWarningRepeatCustom = false
                warningRepeatCustomFocused = false
                warningRepeatPreset = preset
                applyWarningRepeatPreset(preset)
            }
        } label: {
            Text(label)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(NMValueChoiceAppearance.foreground(selected: selected,
                                                                       isEnabled: isEnabled,
                                                                       controlActiveState: controlActiveState))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: settingsCompactSegmentContentHeight)
                .background(NMValueChoiceAppearance.background(selected: selected,
                                                                       isEnabled: isEnabled,
                                                                       controlActiveState: controlActiveState),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func beginWarningRepeatCustomEdit() {
        let stored = settings.dataLimitWarningRepeatMinutes
        if stored > 0, stored != 30, stored != 60 {
            customRepeatMinutes = stored
        }
        warningRepeatCustomText = String(max(1, customRepeatMinutes))
        invalidWarningRepeatCustom = false
        editingWarningRepeatCustom = true
        DispatchQueue.main.async {
            warningRepeatCustomFocused = true
            nmSelectAllCurrentTextEditor()
        }
    }

    private func commitWarningRepeatCustom() {
        let trimmed = warningRepeatCustomText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value >= 1 else {
            invalidWarningRepeatCustom = true
            warningRepeatCustomFocused = true
            return
        }
        customRepeatMinutes = value
        settings.dataLimitWarningRepeatMinutes = value
        warningRepeatPreset = .custom
        warningRepeatCustomText = String(value)
        invalidWarningRepeatCustom = false
        editingWarningRepeatCustom = false
        warningRepeatCustomFocused = false
    }

    private func cancelWarningRepeatCustomEdit() {
        invalidWarningRepeatCustom = false
        editingWarningRepeatCustom = false
        warningRepeatCustomFocused = false
        syncWarningRepeatPreset()
    }

    private var endChoiceBinding: Binding<LimitEndChoice> {
        Binding(get: {
            switch settings.dataLimitPeriodMode {
            case .endDate: return .endDate
            case .selectedMonthEnd: return .selectedMonthEnd
            case .duration: return .fromStart
            }
        }, set: { choice in
            switch choice {
            case .fromStart:
                settings.dataLimitPeriodMode = .duration
            case .selectedMonthEnd:
                settings.dataLimitSelectedEndMonth = calendar.component(.month, from: settings.dataLimitStartDate)
                settings.dataLimitPeriodMode = .selectedMonthEnd
            case .endDate:
                settings.dataLimitPeriodMode = .endDate
            }
        })
    }

    private let warningLightDisabledSentinel = "__off__"
    private let warningLightLimitSentinel = "__limit__"

    private enum WarningLightColor {
        case yellow, orange, red
    }

    private var warningLightYellowRuleBinding: Binding<String> {
        Binding(
            get: {
                let valid = settings.dataLimitWarningRules.contains { $0.id.uuidString == settings.dataLimitWarningLightYellowRuleID }
                if settings.dataLimitWarningLightYellowRuleID == warningLightDisabledSentinel { return warningLightDisabledSentinel }
                return valid ? settings.dataLimitWarningLightYellowRuleID : (settings.dataLimitWarningRules.first?.id.uuidString ?? warningLightDisabledSentinel)
            },
            set: { setWarningLightSelection($0, color: .yellow) }
        )
    }

    private struct WarningLightPickerOption: Identifiable {
        let id: String
        let title: String
    }

    private func warningLightRuleOptions(for color: WarningLightColor) -> [WarningLightPickerOption] {
        let bounds = warningLightStageBounds(for: color)
        func isAllowed(stage: Int) -> Bool {
            if let minimum = bounds.minimumExclusive, stage <= minimum { return false }
            if let maximum = bounds.maximumExclusive, stage >= maximum { return false }
            return true
        }

        var result = [WarningLightPickerOption(id: warningLightDisabledSentinel, title: t("notUsed"))]
        result += settings.dataLimitWarningRules.enumerated().compactMap { index, rule in
            guard isAllowed(stage: index) else { return nil }
            return WarningLightPickerOption(id: rule.id.uuidString, title: warningRuleTitle(index))
        }

        // Yellow remains the earliest caution color and therefore maps only to a
        // warning milestone. Orange/red may use the hard limit when it still fits
        // strictly between the active neighboring colors. This two-sided filter
        // prevents inversions without silently changing another color's choice.
        switch color {
        case .yellow:
            break
        case .orange, .red:
            let limitStage = settings.dataLimitWarningRules.count
            if isAllowed(stage: limitStage) {
                result.append(WarningLightPickerOption(id: warningLightLimitSentinel, title: t("limitReachedShort")))
            }
        }
        return result
    }

    private var warningLightOrangeRuleBinding: Binding<String> {
        Binding(
            get: {
                let validIDs = Set(warningLightRuleOptions(for: .orange).map(\.id))
                return validIDs.contains(settings.dataLimitWarningLightOrangeRuleID)
                    ? settings.dataLimitWarningLightOrangeRuleID
                    : warningLightDisabledSentinel
            },
            set: { setWarningLightSelection($0, color: .orange) }
        )
    }

    private var warningLightRedRuleBinding: Binding<String> {
        Binding(
            get: {
                let validIDs = Set(warningLightRuleOptions(for: .red).map(\.id))
                return validIDs.contains(settings.dataLimitWarningLightRedRuleID)
                    ? settings.dataLimitWarningLightRedRuleID
                    : warningLightDisabledSentinel
            },
            set: { setWarningLightSelection($0, color: .red) }
        )
    }

    @ViewBuilder
    private func warningLightPickerRow(_ emoji: String,
                                       color: WarningLightColor,
                                       selection: Binding<String>,
                                       options: [WarningLightPickerOption]) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(t("warningLightLinkTarget"))
            Spacer(minLength: 10)
            Picker("", selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
                .nmNeutralValueControl()
            .frame(width: 132)
            if selection.wrappedValue != warningLightDisabledSentinel {
                Text(t("fromSuffix")).foregroundStyle(.secondary)
            }
        }
    }

    private func currentWarningLightSelection(for color: WarningLightColor) -> String {
        switch color {
        case .yellow: return settings.dataLimitWarningLightYellowRuleID
        case .orange: return settings.dataLimitWarningLightOrangeRuleID
        case .red: return settings.dataLimitWarningLightRedRuleID
        }
    }

    private func warningLightStage(_ id: String) -> Int? {
        guard id != warningLightDisabledSentinel else { return nil }
        if id == warningLightLimitSentinel { return settings.dataLimitWarningRules.count }
        return settings.dataLimitWarningRules.firstIndex { $0.id.uuidString == id }
    }

    private func warningLightStageBounds(for color: WarningLightColor) -> (minimumExclusive: Int?, maximumExclusive: Int?) {
        let preceding: [WarningLightColor]
        let succeeding: [WarningLightColor]
        switch color {
        case .yellow:
            preceding = []
            succeeding = [.orange, .red]
        case .orange:
            preceding = [.yellow]
            succeeding = [.red]
        case .red:
            preceding = [.yellow, .orange]
            succeeding = []
        }
        let minimum = preceding.compactMap { warningLightStage(currentWarningLightSelection(for: $0)) }.max()
        let maximum = succeeding.compactMap { warningLightStage(currentWarningLightSelection(for: $0)) }.min()
        return (minimum, maximum)
    }

    private func setWarningLightSelection(_ id: String, color: WarningLightColor) {
        let validIDs = Set(warningLightRuleOptions(for: color).map(\.id))
        guard validIDs.contains(id) else { return }
        switch color {
        case .yellow: settings.dataLimitWarningLightYellowRuleID = id
        case .orange: settings.dataLimitWarningLightOrangeRuleID = id
        case .red: settings.dataLimitWarningLightRedRuleID = id
        }
        // Do not rewrite another color as a side effect of a picker action.
        // Neighboring active colors constrain this picker's visible choices, so a
        // user change cannot create a duplicate or inverted severity mapping.
    }

    private func ensureWarningLightRuleSelections() {
        let normalized = SettingsStore.normalizedWarningLightRuleIDs(
            rules: settings.dataLimitWarningRules,
            yellow: settings.dataLimitWarningLightYellowRuleID,
            orange: settings.dataLimitWarningLightOrangeRuleID,
            red: settings.dataLimitWarningLightRedRuleID
        )
        if settings.dataLimitWarningLightYellowRuleID != normalized.yellow { settings.dataLimitWarningLightYellowRuleID = normalized.yellow }
        if settings.dataLimitWarningLightOrangeRuleID != normalized.orange { settings.dataLimitWarningLightOrangeRuleID = normalized.orange }
        if settings.dataLimitWarningLightRedRuleID != normalized.red { settings.dataLimitWarningLightRedRuleID = normalized.red }
    }

    @ViewBuilder
    private var managementPeriodEditor: some View {
        // Data Limit only: the outer skeleton is two columns (label / complete
        // operation area). Inside the operation area, the mode/action slot keeps
        // one stable X anchor and only the trailing value changes. This avoids the
        // Build 114-115 three-column minimum-width overflow while preserving the
        // user's approved stable first-control position.
        Grid(horizontalSpacing: 12, verticalSpacing: 0) {
            managementPeriodOperationRow(t("startPoint")) {
                Button(t("fromNow")) { setLimitStartNow() }
                    .buttonStyle(NMNeutralActionButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
            } value: {
                DatePicker("", selection: $settings.dataLimitStartDate, displayedComponents: [.date, .hourAndMinute])
                    .nmNeutralValueControl()
                    .labelsHidden()
                    .environment(\.locale, dateDisplayLocale)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Divider()
                .gridCellColumns(2)
                .padding(.vertical, 4)

            managementPeriodOperationRow(t("endPoint")) {
                Picker("", selection: endChoiceBinding) {
                    Text(t("fromStart")).tag(LimitEndChoice.fromStart)
                    Text(t("selectedMonthEnd")).tag(LimitEndChoice.selectedMonthEnd)
                    Text(t("selectEndDate")).tag(LimitEndChoice.endDate)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .nmNeutralValueControl()
                .frame(width: managementPeriodModeControlWidth, alignment: .leading)
            } value: {
                managementPeriodTrailingEditor
            }

            Divider()
                .gridCellColumns(2)
                .padding(.vertical, 4)

            managementPeriodResultRow

            Divider()
                .gridCellColumns(2)
                .padding(.vertical, 4)

            managementPeriodAfterEndRow
            managementPeriodAfterEndDetail
        }
        .frame(maxWidth: .infinity)
    }

    private var managementPeriodModeControlWidth: CGFloat {
        [t("fromStart"), t("selectedMonthEnd"), t("selectEndDate")]
            .map(nativeMenuControlWidth)
            .max() ?? 0
    }


    private var managementPeriodModeCenterInset: CGFloat {
        // Keep the approved centerward separation independent of localization.
        // Reusing the localized popup width as padding doubled long English/Spanish
        // labels and could push the whole Settings window wider on page entry.
        settingsCompactSegmentHorizontalPadding * 2
    }

    private func nativeMenuControlWidth(_ title: String) -> CGFloat {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItem(withTitle: title)
        popup.selectItem(at: 0)
        popup.sizeToFit()
        return ceil(popup.frame.width)
    }

    @ViewBuilder
    private var managementPeriodResultRow: some View {
        GridRow {
            Text(endChoiceBinding.wrappedValue == .endDate ? t("period") : t("endDateLabel"))
                .fixedSize(horizontal: true, vertical: false)
                .gridColumnAlignment(.leading)
            Text(endChoiceBinding.wrappedValue == .endDate
                 ? precisePeriodDescription(from: settings.dataLimitStartDate, to: settings.dataLimitEndDate)
                 : dateTimeText(configuredInitialEnd))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var managementPeriodAfterEndRow: some View {
        GridRow {
            Text(t("afterEnd"))
                .fixedSize(horizontal: true, vertical: false)
                .gridColumnAlignment(.leading)
            afterEndBehaviorControl
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var managementPeriodAfterEndDetail: some View {
        GridRow {
            Color.clear.frame(width: 0, height: 0)
            VStack(alignment: .trailing, spacing: 4) {
                switch settings.dataLimitEndBehavior {
                case .stop:
                    SettingsHelpText(t("managementStopHelp"))
                        .multilineTextAlignment(.trailing)
                case .repeatSame:
                    SettingsHelpText(t("cycleRepeatHelp"))
                        .multilineTextAlignment(.trailing)
                case .switchToMonthly:
                    HStack(spacing: 6) {
                        Text(t("everyMonthPrefix")).foregroundStyle(.secondary)
                        TextField("", value: $settings.dataLimitMonthlyStartDay, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .nmSelectAllOnEdit()
                        Text(t("monthlyResetSuffix")).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    SettingsHelpText(t("monthlyMissingDayHelp"))
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .gridColumnAlignment(.trailing)
        }
    }

    private var afterEndBehaviorControl: some View {
        let labels = [t("managementStop"), t("cycleRepeat"), t("monthlyManagement")]
        // Stay content-fit in short locales, but never let long localized labels
        // claim more than the established inline settings lane. Text can scale
        // inside the three equal semantic choices instead of resizing NSWindow.
        let width = min(settingsInlineChoiceWidth, equalSegmentControlWidth(labels))
        let segmentWidth = max(1, (width - 6) / 3)
        return HStack(spacing: 1) {
            afterEndBehaviorChoice(t("managementStop"), behavior: .stop)
                .frame(width: segmentWidth)
            afterEndBehaviorChoice(t("cycleRepeat"), behavior: .repeatSame)
                .frame(width: segmentWidth)
            afterEndBehaviorChoice(t("monthlyManagement"), behavior: .switchToMonthly)
                .frame(width: segmentWidth)
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.6) }
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func afterEndBehaviorChoice(_ label: String, behavior: DataLimitEndBehavior) -> some View {
        let selected = settings.dataLimitEndBehavior == behavior
        return Button { settings.dataLimitEndBehavior = behavior } label: {
            Text(label)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(NMValueChoiceAppearance.foreground(selected: selected,
                                                                       isEnabled: isEnabled,
                                                                       controlActiveState: controlActiveState))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: settingsCompactSegmentContentHeight)
                .background(NMValueChoiceAppearance.background(selected: selected,
                                                                       isEnabled: isEnabled,
                                                                       controlActiveState: controlActiveState),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var managementPeriodTrailingEditor: some View {
        switch endChoiceBinding.wrappedValue {
        case .fromStart:
            HStack(spacing: 6) {
                TextField("", value: $settings.dataLimitPeriodValue, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .nmSelectAllOnEdit()
                Picker("", selection: $settings.dataLimitPeriodUnit) {
                    Text(t("days")).tag(DataLimitPeriodUnit.days)
                    Text(t("months")).tag(DataLimitPeriodUnit.months)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .nmNeutralValueControl()
                .frame(width: 92)
                Text(t("durationSuffix")).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        case .selectedMonthEnd:
            HStack(spacing: 6) {
                TextField("", value: $settings.dataLimitSelectedEndMonth, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .nmSelectAllOnEdit()
                Text(t("monthEndSuffix")).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        case .endDate:
            DatePicker("", selection: $settings.dataLimitEndDate, in: settings.dataLimitStartDate.addingTimeInterval(60)..., displayedComponents: [.date, .hourAndMinute])
                .nmNeutralValueControl()
                .labelsHidden()
                .environment(\.locale, dateDisplayLocale)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func managementPeriodOperationRow<Mode: View, Value: View>(
        _ label: String,
        @ViewBuilder mode: () -> Mode,
        @ViewBuilder value: () -> Value
    ) -> some View {
        GridRow {
            Text(label)
                .fixedSize(horizontal: true, vertical: false)
                .gridColumnAlignment(.leading)
            HStack(spacing: 10) {
                HStack(spacing: 0) { mode() }
                    .frame(width: managementPeriodModeControlWidth, alignment: .leading)
                    .padding(.leading, managementPeriodModeCenterInset)
                Spacer(minLength: 8)
                HStack(spacing: 0) { value() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .gridColumnAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var targetNetworkEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            NMValueChoice(t("targetNetwork"), selection: $settings.dataLimitNetworkTargetMode, options: [
                (.allNetworks, t("allNetworks")), (.selectedNetwork, t("specificNetwork"))
            ])
            SettingsHelpText(t("targetNetworkHelp"))

            if settings.dataLimitNetworkTargetMode == .selectedNetwork {
                Divider()
                HStack(spacing: 10) {
                    Text(t("selectedNetwork"))
                    Spacer(minLength: 10)
                    Text(selectedNetworkStatusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button(t("change")) {
                        interface.refreshWiFiIdentityAuthorizationStatus()
                        if interface.wiFiIdentityAuthorized {
                            interface.refreshWiFiNetworkChoices(scanNearby: false)
                        }
                        showingNetworkChooser = true
                    }
                }
                SettingsHelpText(t("specificNetworkScopeHelp"), level: .detail)
                SettingsHelpText(t("wifiLocationReviewPurpose"))
                if !selectedNetworkIsConfigured {
                    SettingsHelpText(t("networkSelectionIncompleteHelp"))
                } else if !selectedNetworkReliable {
                    SettingsHelpText(t("networkIdentityBestEffortHelp"))
                    if settings.dataLimitNetworkIdentifier.hasPrefix("ethernet:interface:") {
                        SettingsHelpText(t("ethernetIdentityLimitHelp"), level: .detail)
                    }
                }
            }
        }
    }

    private var networkChooserSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("chooseNetwork"))
                .font(.title3.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("currentConnection")).font(.headline)
                        HStack {
                            Text(interface.snapshot.networkDisplayName.isEmpty ? interface.snapshot.interfaceDescription : interface.snapshot.networkDisplayName)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(t("select")) { useCurrentNetwork(); showingNetworkChooser = false }
                                .buttonStyle(NMPrimaryActionButtonStyle())
                                .disabled(interface.snapshot.networkIdentifier.isEmpty)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("savedNetworks")).font(.headline)
                        fixedHeightNetworkChoiceList(knownNetworkChoices, emptyText: t("noSavedNetworks"))
                    }

                    if interface.wiFiIdentityAuthorized {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(t("nearbyNetworks")).font(.headline)
                                Spacer()
                                if interface.isScanningWiFiNetworks { ProgressView().controlSize(.small) }
                                Button { interface.refreshWiFiNetworkChoices(scanNearby: true) } label: { Image(systemName: "arrow.clockwise") }
                                    .buttonStyle(NMUtilityIconButtonStyle())
                                    .disabled(interface.isScanningWiFiNetworks)
                            }
                            fixedHeightNetworkChoiceList(nearbyNetworkChoices, emptyText: t("noNearbyNetworks"))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(interface.wiFiIdentityAuthorizationDenied ? t("openSystemSettings") : t("enableWiFiIdentification")) {
                                if interface.wiFiIdentityAuthorizationDenied || !interface.locationServicesEnabled {
                                    SystemSettingsOpener.openLocationServices()
                                } else {
                                    interface.requestWiFiIdentityAuthorization()
                                }
                            }
                            SettingsHelpText(t("wifiIdentificationChoiceHelp"), level: .detail)
                            SettingsHelpText(t("wifiIdentityPermissionEssential"))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("directInput")).font(.headline)
                        HStack {
                            TextField(t("networkNameSSID"), text: $directNetworkName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { applyDirectNetworkName(); if settings.dataLimitNetworkTargetMode == .selectedNetwork { showingNetworkChooser = false } }
                            Button(t("add")) {
                                applyDirectNetworkName()
                                if settings.dataLimitNetworkTargetMode == .selectedNetwork { showingNetworkChooser = false }
                            }
                            .buttonStyle(NMPrimaryActionButtonStyle())
                            .disabled(directNetworkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .frame(minHeight: 320, maxHeight: 520)

            HStack {
                Button(t("laterChoose")) { deferNetworkSelection(); showingNetworkChooser = false }
                    .buttonStyle(NMNeutralActionButtonStyle())
                Spacer()
                Button(t("close")) { showingNetworkChooser = false }
                    .buttonStyle(NMNeutralActionButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var networkOptions: [RecordedNetworkIdentity] {
        var values: [String: RecordedNetworkIdentity] = [:]
        for network in knownNetworkChoices + nearbyNetworkChoices {
            values[network.id] = network
        }
        let current = interface.snapshot
        if !current.networkIdentifier.isEmpty {
            values[current.networkIdentifier] = RecordedNetworkIdentity(
                id: current.networkIdentifier,
                displayName: current.networkDisplayName.isEmpty ? current.networkIdentifier : current.networkDisplayName,
                reliable: current.networkIdentityReliable
            )
        }
        if settings.dataLimitNetworkTargetMode == .selectedNetwork,
           !settings.dataLimitNetworkIdentifier.isEmpty,
           values[settings.dataLimitNetworkIdentifier] == nil {
            values[settings.dataLimitNetworkIdentifier] = RecordedNetworkIdentity(
                id: settings.dataLimitNetworkIdentifier,
                displayName: settings.dataLimitNetworkDisplayName.isEmpty ? settings.dataLimitNetworkIdentifier : settings.dataLimitNetworkDisplayName,
                reliable: settings.dataLimitNetworkIdentifier.hasPrefix("wifi:ssid:")
            )
        }
        return values.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Saved history and macOS-known Wi-Fi names remain selectable even if the
    /// optional SSID permission is currently unavailable. Nearby discovery stays
    /// separate because it is the only group that requires that permission.
    private var knownNetworkChoices: [RecordedNetworkIdentity] {
        let currentID = interface.snapshot.networkIdentifier
        var used: [String: RecordedNetworkIdentity] = [:]
        for network in recorder.knownNetworks where network.id != currentID && !isInterfaceFallback(network.id) {
            if used[network.id] == nil { used[network.id] = network }
        }
        let usedChoices = used.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        var saved: [String: RecordedNetworkIdentity] = [:]
        for choice in interface.savedWiFiNetworks {
            let network = RecordedNetworkIdentity(id: choice.id, displayName: choice.displayName, reliable: true)
            if used[network.id] == nil { saved[network.id] = network }
        }
        if settings.dataLimitNetworkTargetMode == .selectedNetwork,
           !settings.dataLimitNetworkIdentifier.isEmpty {
            let selected = RecordedNetworkIdentity(
                id: settings.dataLimitNetworkIdentifier,
                displayName: settings.dataLimitNetworkDisplayName.isEmpty ? settings.dataLimitNetworkIdentifier : settings.dataLimitNetworkDisplayName,
                reliable: settings.dataLimitNetworkIdentifier.hasPrefix("wifi:ssid:")
            )
            if selected.id != currentID,
               used[selected.id] == nil,
               !isInterfaceFallback(selected.id) {
                saved[selected.id] = selected
            }
        }
        let savedChoices = saved.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        // Keep past/confirmed choices before remaining macOS-saved choices.
        return usedChoices + savedChoices
    }

    private var nearbyNetworkChoices: [RecordedNetworkIdentity] {
        let excluded = Set(knownNetworkChoices.map(\.id) + [interface.snapshot.networkIdentifier])
        return interface.nearbyWiFiNetworks
            .map { RecordedNetworkIdentity(id: $0.id, displayName: $0.displayName, reliable: true) }
            .filter { !excluded.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func networkChoiceButton(_ network: RecordedNetworkIdentity) -> some View {
        HStack {
            Text(network.displayName)
            Spacer()
            Button(t("select")) {
                selectNetwork(network)
                showingNetworkChooser = false
            }
            .buttonStyle(NMPrimaryActionButtonStyle())
        }
        .frame(height: 30)
    }

    /// Both discovery lists retain a seven-row viewport so Wi-Fi scans and saved
    /// profile changes never make this sheet jump in height. The current network
    /// intentionally remains in its own, unrestricted section above.
    private func fixedHeightNetworkChoiceList(_ networks: [RecordedNetworkIdentity], emptyText: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if networks.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                } else {
                    ForEach(networks) { network in
                        networkChoiceButton(network)
                    }
                }
            }
        }
        .frame(height: 222)
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 0.5)
        }
    }

    private var selectedNetworkIsConfigured: Bool {
        settings.dataLimitNetworkTargetMode != .selectedNetwork || !settings.dataLimitNetworkIdentifier.isEmpty
    }

    private var selectedNetworkStatusText: String {
        guard selectedNetworkIsConfigured else { return t("networkSelectionRequired") }
        return settings.dataLimitNetworkDisplayName.isEmpty
            ? settings.dataLimitNetworkIdentifier
            : settings.dataLimitNetworkDisplayName
    }

    private var selectedNetworkReliable: Bool {
        guard settings.dataLimitNetworkTargetMode == .selectedNetwork else { return true }
        return networkOptions.first(where: { $0.id == settings.dataLimitNetworkIdentifier })?.reliable
            ?? settings.dataLimitNetworkIdentifier.hasPrefix("wifi:ssid:")
    }

    private func useCurrentNetwork() {
        let snapshot = interface.snapshot
        guard !snapshot.networkIdentifier.isEmpty else { return }
        settings.dataLimitNetworkTargetMode = .selectedNetwork
        settings.dataLimitNetworkIdentifier = snapshot.networkIdentifier
        settings.dataLimitNetworkDisplayName = snapshot.networkDisplayName.isEmpty ? snapshot.networkIdentifier : snapshot.networkDisplayName
    }

    private func selectNetwork(_ network: RecordedNetworkIdentity) {
        settings.dataLimitNetworkTargetMode = .selectedNetwork
        settings.dataLimitNetworkIdentifier = network.id
        settings.dataLimitNetworkDisplayName = network.displayName
    }

    private func deferNetworkSelection() {
        // Do not silently turn a deliberately selected per-network plan into an
        // all-networks plan. An empty target is an explicit incomplete state and
        // UsageRecorder consequently keeps its warning/block action fail-open.
        settings.dataLimitNetworkTargetMode = .selectedNetwork
        settings.dataLimitNetworkIdentifier = ""
        settings.dataLimitNetworkDisplayName = ""
    }

    private func isInterfaceFallback(_ identifier: String) -> Bool {
        identifier.hasPrefix("wifi:interface:") || identifier.hasPrefix("network:interface:utun")
    }

    private func applyDirectNetworkName() {
        let name = directNetworkName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        settings.dataLimitNetworkTargetMode = .selectedNetwork
        settings.dataLimitNetworkIdentifier = "wifi:ssid:\(name)"
        settings.dataLimitNetworkDisplayName = name
        directNetworkName = ""
    }

    private func migrateSelectedNetworkIdentityIfNeeded(_ newIdentifier: String) {
        let previousIdentifier = settings.dataLimitNetworkIdentifier
        let wasWiFiInterfaceFallback = previousIdentifier.hasPrefix("wifi:interface:")
        let wasVPNRouteFallback = previousIdentifier.hasPrefix("network:interface:utun")
        guard settings.dataLimitNetworkTargetMode == .selectedNetwork,
              wasWiFiInterfaceFallback || wasVPNRouteFallback,
              newIdentifier.hasPrefix("wifi:ssid:"),
              interface.snapshot.networkIdentityReliable else { return }
        // If the user selected the current connection before SSID permission was
        // available, replace that temporary interface/VPN-route identity with the
        // newly proven SSID. Directly entered/saved SSIDs are never rewritten.
        settings.dataLimitNetworkIdentifier = newIdentifier
        settings.dataLimitNetworkDisplayName = interface.snapshot.networkDisplayName.isEmpty
            ? newIdentifier
            : interface.snapshot.networkDisplayName
    }

    private func setLimitStartNow() {
        let now = Date()
        settings.dataLimitStartDate = now
        settings.dataLimitSelectedEndMonth = calendar.component(.month, from: now)
        settings.dataLimitMonthlyStartDay = calendar.component(.day, from: now)
        settings.dataLimitStartingRemainingApplied = false
        if settings.dataLimitPeriodMode == .endDate, settings.dataLimitEndDate <= now {
            settings.dataLimitEndDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        }
    }

    private var configuredInitialEnd: Date {
        switch settings.dataLimitPeriodMode {
        case .endDate:
            return max(settings.dataLimitEndDate, settings.dataLimitStartDate.addingTimeInterval(60))
        case .selectedMonthEnd:
            return selectedMonthEndDate(start: settings.dataLimitStartDate, month: settings.dataLimitSelectedEndMonth)
        case .duration:
            let value = max(1, settings.dataLimitPeriodValue)
            switch settings.dataLimitPeriodUnit {
            case .days:
                return calendar.date(byAdding: .day, value: value, to: settings.dataLimitStartDate)
                    ?? settings.dataLimitStartDate.addingTimeInterval(TimeInterval(value) * 86400)
            case .months:
                return calendar.date(byAdding: .month, value: value, to: settings.dataLimitStartDate)
                    ?? settings.dataLimitStartDate.addingTimeInterval(TimeInterval(value) * 30 * 86400)
            }
        }
    }

    private func selectedMonthEndDate(start: Date, month: Int) -> Date {
        let startMonth = calendar.component(.month, from: start)
        var year = calendar.component(.year, from: start)
        let clampedMonth = min(12, max(1, month))
        if clampedMonth < startMonth { year += 1 }
        var comps = DateComponents(year: year, month: clampedMonth + 1, day: 1, hour: 0, minute: 0, second: 0)
        if clampedMonth == 12 { comps = DateComponents(year: year + 1, month: 1, day: 1, hour: 0, minute: 0, second: 0) }
        let nextMonth = calendar.date(from: comps) ?? start.addingTimeInterval(86400)
        return nextMonth.addingTimeInterval(-1)
    }

    private func warningRuleBinding(id: UUID, fallback: DataLimitWarningRule) -> Binding<DataLimitWarningRule> {
        Binding(
            get: { settings.dataLimitWarningRules.first(where: { $0.id == id }) ?? fallback },
            set: { value in
                var rules = settings.dataLimitWarningRules
                guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
                rules[index] = value
                settings.dataLimitWarningRules = rules
            }
        )
    }

    @ViewBuilder
    private func warningRuleEditor(ruleID: UUID, displayIndex: Int, fallback: DataLimitWarningRule) -> some View {
        let rule = warningRuleBinding(id: ruleID, fallback: fallback)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(warningRuleTitle(displayIndex))
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    removeWarningRule(id: ruleID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(NMDestructiveIconButtonStyle())
                .disabled(settings.dataLimitWarningRules.count <= 1)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(t("warningTiming"))
                Spacer(minLength: 10)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(t("remainingData"))
                            .foregroundStyle(.secondary)
                        TextField("", value: warningValueBinding(id: ruleID, fallback: fallback), format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .nmSelectAllOnEdit()
                        Picker(t("unit"), selection: warningUnitBinding(id: ruleID, fallback: fallback)) {
                            ForEach(WarningThresholdUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                .nmNeutralValueControl()
                        .frame(width: 78)
                    }
                    SettingsHelpText(warningMeaningText(rule.wrappedValue), level: .detail)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func addWarningRule() {
        guard settings.dataLimitWarningRules.count < SettingsStore.maximumDataLimitWarningRules else { return }
        let existing = settings.dataLimitWarningRules.last.map(remainingBytes(for:)) ?? settings.dataLimitBytes
        let remaining = max(1, existing / 2)
        settings.dataLimitWarningRules.append(ruleForRemainingBytes(remaining, preferredUnit: .percentage))
        normalizeWarningRuleOrder()
        if settings.dataLimitWarningLightLinked { ensureWarningLightRuleSelections() }
    }

    private func removeWarningRule(id: UUID) {
        guard settings.dataLimitWarningRules.count > 1,
              let index = settings.dataLimitWarningRules.firstIndex(where: { $0.id == id }) else { return }
        var rules = settings.dataLimitWarningRules
        rules.remove(at: index)
        settings.dataLimitWarningRules = rules
        if settings.dataLimitWarningLightYellowRuleID == id.uuidString {
            settings.dataLimitWarningLightYellowRuleID = rules.first?.id.uuidString ?? warningLightDisabledSentinel
        }
        if settings.dataLimitWarningLightOrangeRuleID == id.uuidString {
            settings.dataLimitWarningLightOrangeRuleID = warningLightDisabledSentinel
        }
        if settings.dataLimitWarningLightRedRuleID == id.uuidString {
            settings.dataLimitWarningLightRedRuleID = warningLightLimitSentinel
        }
        if settings.dataLimitWarningLightLinked { ensureWarningLightRuleSelections() }
        normalizeWarningRuleOrder()
    }

    private func warningRuleTitle(_ index: Int) -> String {
        switch index {
        case 0: return t("firstWarning")
        case 1: return t("secondWarning")
        case 2: return t("thirdWarning")
        default: return String(format: t("warningNumber"), index + 1)
        }
    }

    private func remainingBytes(for rule: DataLimitWarningRule) -> UInt64 {
        let limit = settings.dataLimitBytes
        switch rule.mode {
        case .percentage:
            let remainingPercent = max(1, min(99, 100 - rule.percentage))
            return UInt64(Double(limit) * remainingPercent / 100)
        case .remainingAmount:
            return min(limit, rule.remainingBytes)
        }
    }

    private func warningUnit(for rule: DataLimitWarningRule) -> WarningThresholdUnit {
        switch rule.mode {
        case .percentage: return .percentage
        case .remainingAmount:
            switch rule.remainingUnit {
            case .terabytes: return .terabytes
            case .gigabytes: return .gigabytes
            case .megabytes: return .megabytes
            }
        }
    }

    private func warningValue(for rule: DataLimitWarningRule) -> Double {
        rule.mode == .percentage ? max(1, min(99, 100 - rule.percentage)) : rule.remainingValue
    }

    private func warningValueBinding(id: UUID, fallback: DataLimitWarningRule) -> Binding<Double> {
        Binding(get: { warningValue(for: warningRuleBinding(id: id, fallback: fallback).wrappedValue) }, set: { value in
            let current = warningRuleBinding(id: id, fallback: fallback).wrappedValue
            let unit = warningUnit(for: current)
            let desired: UInt64
            if unit == .percentage {
                desired = UInt64(Double(settings.dataLimitBytes) * min(99, max(1, value)) / 100)
            } else {
                desired = UInt64(min(max(0, value) * (unit.dataLimitUnit?.byteMultiplier ?? 1), Double(UInt64.max)))
            }
            updateWarningRule(id: id, remainingBytes: desired, preferredUnit: unit)
        })
    }

    private func warningUnitBinding(id: UUID, fallback: DataLimitWarningRule) -> Binding<WarningThresholdUnit> {
        Binding(get: { warningUnit(for: warningRuleBinding(id: id, fallback: fallback).wrappedValue) }, set: { unit in
            let current = warningRuleBinding(id: id, fallback: fallback).wrappedValue
            updateWarningRule(id: id, remainingBytes: remainingBytes(for: current), preferredUnit: unit)
        })
    }

    private func updateWarningRule(id: UUID, remainingBytes desired: UInt64, preferredUnit: WarningThresholdUnit) {
        guard let index = settings.dataLimitWarningRules.firstIndex(where: { $0.id == id }) else { return }
        let clamped = clampedRemainingBytes(desired, at: index)
        var rules = settings.dataLimitWarningRules
        rules[index] = ruleForRemainingBytes(clamped, preferredUnit: preferredUnit, id: id)
        settings.dataLimitWarningRules = rules
    }

    private func clampedRemainingBytes(_ desired: UInt64, at index: Int) -> UInt64 {
        let rules = settings.dataLimitWarningRules
        let previous = index > 0 ? remainingBytes(for: rules[index - 1]) : settings.dataLimitBytes
        let upper = previous > 0 ? previous - 1 : 0
        let following = index + 1 < rules.count ? remainingBytes(for: rules[index + 1]) : 0
        let lower = following < UInt64.max ? following + 1 : UInt64.max
        return min(max(desired, lower), max(lower, upper))
    }

    private func ruleForRemainingBytes(_ bytes: UInt64, preferredUnit: WarningThresholdUnit, id: UUID = UUID()) -> DataLimitWarningRule {
        let limit = max(UInt64(1), settings.dataLimitBytes)
        if preferredUnit == .percentage {
            let remainingPercent = min(99, max(1, (Double(bytes) / Double(limit)) * 100))
            return DataLimitWarningRule(id: id, mode: .percentage, percentage: 100 - remainingPercent)
        }
        let unit = preferredUnit.dataLimitUnit ?? .gigabytes
        return DataLimitWarningRule(id: id, mode: .remainingAmount, remainingValue: Double(bytes) / unit.byteMultiplier, remainingUnit: unit)
    }

    private func warningMeaningText(_ rule: DataLimitWarningRule) -> String {
        let limitText = SpeedFormatter.bytes(settings.dataLimitBytes)
        if rule.mode == .percentage {
            return String(format: t("warningRemainingPercentMeaning"), limitText, SpeedFormatter.bytes(remainingBytes(for: rule)))
        }
        let percent = settings.dataLimitBytes > 0 ? (Double(remainingBytes(for: rule)) / Double(settings.dataLimitBytes)) * 100 : 0
        return String(format: t("warningRemainingAmountMeaning"), limitText, percent)
    }

    private func normalizeWarningRuleOrder() {
        let sorted = settings.dataLimitWarningRules.sorted { remainingBytes(for: $0) > remainingBytes(for: $1) }
        if sorted != settings.dataLimitWarningRules { settings.dataLimitWarningRules = sorted }
    }

    private func syncWarningRepeatPreset() {
        switch settings.dataLimitWarningRepeatMinutes {
        case 0:
            warningRepeatPreset = .once
        case 30:
            warningRepeatPreset = .min30
        case 60:
            warningRepeatPreset = .hour1
        default:
            warningRepeatPreset = .custom
            customRepeatMinutes = max(1, settings.dataLimitWarningRepeatMinutes)
        }
        warningRepeatCustomText = String(max(1, customRepeatMinutes))
    }

    private func applyWarningRepeatPreset(_ preset: WarningRepeatPreset) {
        switch preset {
        case .once:
            settings.dataLimitWarningRepeatMinutes = 0
        case .min30:
            settings.dataLimitWarningRepeatMinutes = 30
        case .hour1:
            settings.dataLimitWarningRepeatMinutes = 60
        case .custom:
            break
        }
    }

    private func applyCurrentPlanState() {
        let inputBytesDouble = max(0, balanceValue) * balanceUnit.byteMultiplier
        let inputBytes = UInt64(min(inputBytesDouble, Double(UInt64.max)))
        let limit = settings.dataLimitBytes
        let remaining: UInt64
        switch balanceMode {
        case .used:
            remaining = limit > inputBytes ? limit - inputBytes : 0
        case .remaining:
            remaining = min(limit, inputBytes)
        }
        settings.dataLimitStartingRemainingBytes = Double(remaining)
        settings.dataLimitStartingRemainingApplied = true
    }

    private var startingRemainingDataLimitBytes: UInt64 {
        guard settings.dataLimitStartingRemainingApplied else { return settings.dataLimitBytes }
        let raw = settings.dataLimitStartingRemainingBytes
        let remaining = raw.isFinite ? min(max(0, raw), Double(UInt64.max)) : 0
        return min(settings.dataLimitBytes, UInt64(remaining))
    }

    private var remainingLimitText: String {
        let bytes = startingRemainingDataLimitBytes
        let gigabyte = UInt64(DataLimitUnit.gigabytes.byteMultiplier)
        let megabyte = UInt64(DataLimitUnit.megabytes.byteMultiplier)
        let gigabytes = bytes / gigabyte
        let megabytes = (bytes % gigabyte) / megabyte
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale(for: settings.language)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        let formattedGigabytes = formatter.string(from: NSNumber(value: gigabytes)) ?? String(gigabytes)
        let formattedMegabytes = formatter.string(from: NSNumber(value: megabytes)) ?? String(megabytes)
        return megabytes == 0 ? "\(formattedGigabytes) GB" : "\(formattedGigabytes) GB \(formattedMegabytes) MB"
    }

    private var dateDisplayLocale: Locale {
        L10n.locale(for: settings.language)
    }

    private func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func precisePeriodDescription(from start: Date, to end: Date) -> String {
        let components = calendar.dateComponents([.day, .hour, .minute], from: start, to: max(end, start))
        return String(format: t("periodDurationFormat"),
                      max(0, components.day ?? 0),
                      max(0, components.hour ?? 0),
                      max(0, components.minute ?? 0))
    }

    private var displayedDataUsageRecords: [DataUsageRecord] {
        recorder.recentDataUsageRecords.sorted { $0.start > $1.start }
    }

    private var exportableDataUsageRecords: [DataUsageRecord] {
        recorder.dataUsageRecords.sorted { $0.start > $1.start }
    }

    private func deleteDataUsageRecord(_ record: DataUsageRecord) {
        recorder.deleteDataUsageRecord(id: record.id)
    }

    private func clearAllDataUsageRecords() {
        recorder.clearDataUsageRecords()
    }

    private func exportDataUsageRecords(_ records: [DataUsageRecord], format: UsageExportFormat) {
        guard !records.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = t("dataUsageRecordExportTitle")
        switch format {
        case .xlsx:
            panel.nameFieldStringValue = records.count == 1 ? "NeManeem-data-usage-record.xlsx" : "NeManeem-data-usage-records.xlsx"
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        case .csv:
            panel.nameFieldStringValue = records.count == 1 ? "NeManeem-data-usage-record.csv" : "NeManeem-data-usage-records.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .xlsx: try recorder.exportDataUsageRecordsXLSX(records, destination: url)
            case .csv: try recorder.exportDataUsageRecordsCSV(records, destination: url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = t("dataUsageRecordExportTitle")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private var recordTotals: [UInt64] { displayedDataUsageRecords.map(\.total) }
    private var recordAverage: String {
        guard !recordTotals.isEmpty else { return "—" }
        return SpeedFormatter.bytes(recordTotals.reduce(0, &+) / UInt64(recordTotals.count))
    }
    private var recordMaximum: String { recordTotals.max().map(SpeedFormatter.bytes) ?? "—" }
    private var recordMinimum: String { recordTotals.min().map(SpeedFormatter.bytes) ?? "—" }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }

    private func recordRange(_ record: DataUsageRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = dateDisplayLocale
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return "\(formatter.string(from: record.start))–\(formatter.string(from: record.end))"
    }
}

// MARK: - Settings 6. Troubleshooting

