import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct NetworkSettingsView: View {
    let highlight: String?
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @ObservedObject private var traffic = AppEnvironment.shared.appTrafficMonitor
    @ObservedObject private var interface = AppEnvironment.shared.interfaceMonitor
    @State private var showingCatalogReset = false
    @State private var expandedAppControlIDs: Set<String> = []
    @State private var systemProcessesExpanded = false
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    private var localTrafficDisplaySelectionHelp: String {
        switch settings.localTrafficStatisticsMode {
        case .separate: return t("localSeparateHelp")
        case .combined: return t("localCombinedHelp")
        case .hidden: return t("localHiddenHelp")
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            Form {
                Section {
                    Toggle(t("separateLocalTraffic"), isOn: $settings.separateLocalTraffic)
                    Group {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker(t("localTrafficStats"), selection: $settings.localTrafficStatisticsMode) {
                                Text(t("localSeparate")).tag(LocalTrafficStatisticsMode.separate)
                                Text(t("localCombined")).tag(LocalTrafficStatisticsMode.combined)
                                Text(t("localHidden")).tag(LocalTrafficStatisticsMode.hidden)
                            }
                            .pickerStyle(.menu)
                            .nmNeutralValueControl()
                            SettingsHelpText(localTrafficDisplaySelectionHelp)
                        }
                        SettingsHelpText(t("localTrafficDisplayLimitUnaffectedHelp"))

                        NMValueChoice(t("menuBarScope"), selection: $settings.menuBarTrafficScope, options: [
                            (.internetOnly, t("excludeLocalNetwork")),
                            (.allTraffic, t("allTraffic"))
                        ])
                    }
                    .disabled(!settings.separateLocalTraffic)
                } header: {
                    SettingsSectionHeader(t("localNetwork"), help: t("localTrafficClassificationCaution"), detailHelp: t("localTrafficClassificationDetail"))
                }
                .modifier(SettingsHighlightBackground(active: highlight == "local"))

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("safariNetworkServiceGrouping"), isOn: $settings.safariNetworkServiceGroupingEnabled)
                        VStack(alignment: .leading, spacing: 3) {
                            SettingsHelpText(t("safariGroupingResult"))
                            SettingsHelpText(t("safariGroupingCaution"))
                            SettingsHelpText(t("safariGroupingDetail"), level: .detail)
                        }
                    }

                    Toggle(t("enableFilter"), isOn: Binding(
                        get: { firewall.engineIsEnabled && firewall.isEnabled },
                        set: { firewall.setEnabled($0) }
                    ))
                    .disabled(firewall.isBusy || !firewall.engineIsEnabled)

                    if firewall.engineIsEnabled {
                        SettingsHelpText(t("appBlockingExistingConnectionsHelp"))

                        if settings.expertFeaturesEnabled && firewall.isEnabled {
                            Toggle(t("processBlockingEnabled"), isOn: Binding(
                                get: { firewall.processBlockingEnabled },
                                set: { firewall.setProcessBlockingEnabled($0) }
                            ))
                            .disabled(firewall.isBusy)
                            SettingsHelpText(t("processBlockingSafetyHelp"), level: .detail)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            SettingsHelpText(t("appBlockingNeedsNetworkMonitoringHelp"))
                            HStack {
                                Spacer()
                                Button(appBlockingSetupActionTitle) {
                                    openAppBlockingSetup()
                                }
                                .disabled(firewall.isBusy)
                            }
                        }
                    }

                    if let message = firewall.statusMessage {
                        Text(message.localizedCaseInsensitiveContains("entitlement") ? t("signingRequired") : message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if firewall.engineIsEnabled {
                        HStack {
                            Text(processBlockingActive
                                 ? String(format: t("observedProcessCountFormat"), observedProcessRows.count)
                                 : String(format: t("observedAppCountFormat"), observedAppGroups.count))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(t("resetObservedApps"), role: .destructive) {
                                showingCatalogReset = true
                            }
                            .buttonStyle(NMDestructiveSecondaryButtonStyle())
                            .disabled(processBlockingActive ? observedProcessRows.isEmpty : (observedAppGroups.isEmpty && systemRows.isEmpty))
                        }

                        if processBlockingActive {
                            processControlList
                        } else if observedAppGroups.isEmpty && systemRows.isEmpty {
                            SettingsHelpText(t("noObservedApps"))
                        } else {
                            HStack(spacing: 10) {
                                Text(t("processName"))
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(t("allowed"))
                                    .font(.callout.weight(.semibold))
                                    .frame(width: 58, alignment: .center)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)

                            if !observedAppGroups.isEmpty {
                                ForEach(observedAppGroups) { group in
                                    appControlRow(group)
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            if let usage = group.members.first {
                                                networkIdentityContextMenu(usage, preferProcess: false)
                                            }
                                        }
                                }
                            }
                            if !systemRows.isEmpty {
                                Button {
                                    systemProcessesExpanded.toggle()
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: systemProcessesExpanded ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 12)
                                        Text("\(t("systemProcesses")) \(systemRows.count)")
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if systemProcessesExpanded {
                                    VStack(spacing: 0) {
                                        ForEach(systemRows) { usage in
                                            processControlRow(usage)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader(t("networkControl"), help: t("networkControlStableHelp"), detailHelp: t("appListGroupingHelp"))
                }
                .modifier(SettingsHighlightBackground(active: highlight == "control"))
            }
            .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        }
        .confirmationDialog(t("resetObservedAppsConfirm"), isPresented: $showingCatalogReset) {
            Button(t("resetObservedApps"), role: .destructive) {
                traffic.clearObservedCatalog()
                settings.manualParentAppMappings = [:]
            }
        }
        .onAppear {
            traffic.hydrateObservedCatalogAfterLaunch()
            traffic.enrichObservedCatalogMetadataIncrementally()
            traffic.setDemand(.settingsNetwork, active: true)
        }
        .onDisappear { traffic.setDemand(.settingsNetwork, active: false) }
    }

    private var appBlockingSetupNeedsTroubleshooting: Bool {
        !firewall.engineIsEnabled && firewall.statusMessage != nil && !firewall.extensionNeedsUserApproval
    }

    private var appBlockingSetupActionTitle: String {
        appBlockingSetupNeedsTroubleshooting ? t("troubleshooting") : t("networkMonitoringSettings")
    }

    private func openAppBlockingSetup() {
        if appBlockingSetupNeedsTroubleshooting {
            AppEnvironment.shared.requestSettingsSection?("troubleshooting")
        } else {
            SystemSettingsOpener.openNetworkExtensions()
        }
    }

    @ViewBuilder
    private func networkIdentityContextMenu(_ usage: AppNetworkUsage, preferProcess: Bool) -> some View {
        AppIdentityContextMenuContent(usage: usage, preferProcess: preferProcess)
    }

    @ViewBuilder
    private func appControlRow(_ group: AppSelectionGroup) -> some View {
        if expertNetworkControlDetailsActive && appControlHasProcessDetails(group) {
            VStack(spacing: 2) {
                HStack(spacing: 10) {
                    Button {
                        if expandedAppControlIDs.contains(group.id) { expandedAppControlIDs.remove(group.id) }
                        else { expandedAppControlIDs.insert(group.id) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: expandedAppControlIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            appControlIdentity(group)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    appControlPermission(group)
                }
                if expandedAppControlIDs.contains(group.id) {
                    VStack(spacing: 0) {
                        ForEach(appControlProcessMembers(group)) { usage in
                            processDetailRow(usage)
                        }
                    }
                }
            }
        } else {
            appControlLabel(group)
        }
    }

    @ViewBuilder
    private var processControlList: some View {
        if observedProcessRows.isEmpty {
            SettingsHelpText(t("noObservedProcesses"))
        } else {
            HStack(spacing: 10) {
                Text(t("process")).font(.callout.weight(.semibold))
                Spacer()
                Text(t("allowed"))
                    .font(.callout.weight(.semibold))
                    .frame(width: 58, alignment: .center)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)

            ForEach(observedProcessRows) { usage in
                processControlRow(usage)
            }
        }
    }

    private func appControlLabel(_ group: AppSelectionGroup) -> some View {
        HStack(spacing: 10) {
            appControlIdentity(group)
            Spacer()
            appControlPermission(group)
        }
    }

    private func appControlIdentity(_ group: AppSelectionGroup) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: group.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Text(group.displayName).lineLimit(1)
        }
    }

    @ViewBuilder
    private func appControlPermission(_ group: AppSelectionGroup) -> some View {
        if let bundleIdentifier = group.bundleIdentifier {
            Toggle("", isOn: Binding(
                get: { firewall.isAllowed(bundleIdentifier) },
                set: { firewall.setAllowed($0, bundleIdentifier: bundleIdentifier) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!firewall.isEnabled)
            .frame(width: 58, alignment: .center)
        } else {
            Text("—").foregroundStyle(.tertiary).frame(width: 58, alignment: .center)
        }
    }

    private func processDetailRow(_ usage: AppNetworkUsage) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: usage.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(usage.displayName).lineLimit(1)
                if let processIdentifier = usage.processIdentifier, !processIdentifier.isEmpty {
                    Text(processIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("—")
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .center)
        }
        .padding(.leading, 8)
        .contentShape(Rectangle())
        .contextMenu {
            networkIdentityContextMenu(usage, preferProcess: true)
        }
    }

    private var expertNetworkControlDetailsActive: Bool {
        settings.expertFeaturesEnabled && settings.resourceMode != .austerity
    }

    private var processBlockingActive: Bool {
        settings.expertFeaturesEnabled && firewall.isEnabled && firewall.processBlockingEnabled
    }

    private func appControlHasProcessDetails(_ group: AppSelectionGroup) -> Bool {
        appControlProcessMembers(group).contains { usage in
            guard let processIdentifier = usage.processIdentifier, !processIdentifier.isEmpty else { return false }
            return processIdentifier != group.bundleIdentifier || usage.id != group.id
        } || group.members.count > 1
    }

    private func appControlProcessMembers(_ group: AppSelectionGroup) -> [AppNetworkUsage] {
        group.members.sorted { lhs, rhs in
            lhs.displayName.compare(rhs.displayName,
                                    options: [.caseInsensitive, .diacriticInsensitive],
                                    range: nil,
                                    locale: sortLocale) == .orderedAscending
        }
    }

    private func processControlRow(_ usage: AppNetworkUsage) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: usage.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(usage.displayName).lineLimit(1)
                if let processIdentifier = usage.processIdentifier {
                    Text(processIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if processBlockingActive,
               canBlockProcess(usage),
               let processIdentifier = usage.processIdentifier {
                Toggle("", isOn: Binding(
                    get: { firewall.isProcessAllowed(processIdentifier) },
                    set: { firewall.setProcessAllowed($0, processIdentifier: processIdentifier) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!firewall.isEnabled)
                .frame(width: 58, alignment: .center)
            } else if !processBlockingActive, let bundleIdentifier = usage.bundleIdentifier {
                // The ordinary app-blocking view keeps its established bundle-ID
                // rule and system-process disclosure behavior. Process rules are
                // a separate expert-only mode, never a silent replacement.
                Toggle("", isOn: Binding(
                    get: { firewall.isAllowed(bundleIdentifier) },
                    set: { firewall.setAllowed($0, bundleIdentifier: bundleIdentifier) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!firewall.isEnabled)
                .frame(width: 58, alignment: .center)
            } else {
                Text("—").foregroundStyle(.tertiary).frame(width: 58, alignment: .center)
            }
        }
        .padding(.leading, 8)
    }

    private var mappedObservedUsages: [AppNetworkUsage] {
        applyingManualParentMappings(traffic.observedUsages, mappings: settings.manualParentAppMappings)
    }

    private var classifiedObservedUsages: AppSystemUsageSplit {
        splitAppAndSystemUsages(mappedObservedUsages.filter { !isNeManeemControlInternal($0) })
    }

    private var observedAppGroups: [AppSelectionGroup] {
        appSelectionGroups(classifiedObservedUsages.apps).sorted { lhs, rhs in
            lhs.displayName.compare(rhs.displayName,
                                    options: [.caseInsensitive, .diacriticInsensitive],
                                    range: nil,
                                    locale: sortLocale) == .orderedAscending
        }
    }

    private var systemRows: [AppNetworkUsage] {
        classifiedObservedUsages.systemServices.sorted { lhs, rhs in
            lhs.displayName.compare(rhs.displayName,
                                    options: [.caseInsensitive, .diacriticInsensitive],
                                    range: nil,
                                    locale: sortLocale) == .orderedAscending
        }
    }

    private var observedProcessRows: [AppNetworkUsage] {
        var values: [String: AppNetworkUsage] = [:]
        for usage in mappedObservedUsages where !isNeManeemControlInternal(usage) {
            guard let processIdentifier = usage.processIdentifier,
                  !processIdentifier.isEmpty,
                  values[processIdentifier] == nil else { continue }
            values[processIdentifier] = usage
        }
        return values.values.sorted { lhs, rhs in
            lhs.displayName.compare(rhs.displayName,
                                    options: [.caseInsensitive, .diacriticInsensitive],
                                    range: nil,
                                    locale: sortLocale) == .orderedAscending
        }
    }

    private func canBlockProcess(_ usage: AppNetworkUsage) -> Bool {
        guard let identifier = usage.processIdentifier, !identifier.isEmpty else { return false }
        return !usage.isSystemProcess &&
            !identifier.hasPrefix("__nemaneem.") &&
            !identifier.hasPrefix(AppConstants.appBundleIdentifier) &&
            identifier.lowercased() != "unicornprod" &&
            !identifier.lowercased().hasSuffix(".unicornprod")
    }

    private func isNeManeemControlInternal(_ usage: AppNetworkUsage) -> Bool {
        let identifiers = [usage.id, usage.bundleIdentifier, usage.processIdentifier].compactMap { $0 }
        return identifiers.contains { identifier in
            identifier == AppConstants.appBundleIdentifier ||
            identifier == AppConstants.filterBundleIdentifier ||
            identifier.hasPrefix(AppConstants.appBundleIdentifier + ".")
        }
    }

    private var sortLocale: Locale {
        switch settings.language {
        case .korean: return Locale(identifier: "ko_KR")
        case .english: return Locale(identifier: "en_US")
        case .japanese: return Locale(identifier: "ja_JP")
        case .spanish: return Locale(identifier: "es_ES")
        case .system: return .current
        }
    }
}

// MARK: - Settings 4. Usage

