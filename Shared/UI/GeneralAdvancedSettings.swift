import AppKit
import Combine
import CoreLocation
import SwiftUI

struct ResourceModeSettingsSection: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @State private var comparisonExpanded = false
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        Section(t("resourceModeTitle")) {
            NMValueChoice(t("resourceModeTitle"), selection: $settings.resourceMode, options: resourceModeOptions, controlWidth: ResourceModeChoiceGeometry.controlWidth)
            SettingsHelpText(modeDescription, level: .detail)

            if settings.resourceMode == .austerity {
                Toggle(t("austerityKeepTotalHistory"), isOn: $settings.austerityKeepTotalHistory)
                SettingsHelpText(t("austerityKeepTotalHistoryHelp"), level: .detail)
            }

            Button {
                comparisonExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: comparisonExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(t("resourceModeComparison"))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if comparisonExpanded {
                ResourceModeComparisonTable(selected: settings.resourceMode, t: t)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
    }

    private var resourceModeOptions: [(ResourceMode, String)] {
        ResourceMode.allCases.map { ($0, t("resourceMode.\($0.rawValue)")) }
    }

    private var modeDescription: String {
        t("resourceModeDescription.\(settings.resourceMode.rawValue)")
    }
}

private enum ResourceModeChoiceGeometry {
    static let controlWidth = settingsInlineChoiceWidth
    static func columnWidths(_ labels: [String]) -> [CGFloat] {
        compactSegmentWidths(labels, totalWidth: controlWidth)
    }
}

private struct ResourceModeComparisonTable: View {
    let selected: ResourceMode
    let t: (String) -> String

    private let modes: [ResourceMode] = ResourceMode.allCases
    private var modeColumnWidths: [CGFloat] {
        ResourceModeChoiceGeometry.columnWidths(modes.map { t("resourceMode.\($0.rawValue)") })
    }

    var body: some View {
        VStack(spacing: 0) {
            row(title: "", values: modes.map { t("resourceMode.\($0.rawValue)") }, header: true)
            row(title: t("cmpOverallLive"), values: ["●", "●", "●", "●"])
            row(title: t("cmpTotalHistory"), values: ["●", "●", "●", "●"])
            row(title: t("cmpDataLimit"), values: ["●", "●", "●", "●"])
            row(title: t("cmpAppLive"), values: ["—", "●", "●", "●"])
            row(title: t("cmpAppHistory"), values: ["—", "●", "●", "●"])
            row(title: t("cmpResponsiveness"), values: [t("cmpMinimal"), t("cmpSaver"), t("cmpBalanced"), t("cmpFast")])
            row(title: t("cmpResourceSaving"), values: [t("cmpMaximum"), t("cmpHigh"), t("cmpBalanced"), t("cmpResponseFirst")])
            Divider().padding(.vertical, 3)
            HStack { Text(t("expertFeatures")).font(.callout.weight(.semibold)).foregroundStyle(.secondary); Spacer() }
                .padding(.horizontal, 8).padding(.vertical, 5)
            row(title: t("cmpSearchFilterSort"), values: ["—", t("onRequest"), "●", "●"])
            row(title: t("cmpProcessDetails"), values: ["—", t("onRequest"), "●", "●"])
            row(title: t("cmpCopyInfo"), values: ["—", "●", "●", "●"])
            row(title: t("cmpCSV"), values: ["—", "●", "●", "●"])
        }
        // Stay inside the section's native card instead of drawing a second nested
        // card. The right-side mode columns share the chooser's exact geometry.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(title: String, values: [String], header: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(header ? .callout.weight(.semibold) : .callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
            HStack(spacing: 1) {
                ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                    Text(values.indices.contains(index) ? values[index] : "")
                        .font(.callout.weight(header ? .semibold : .regular))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.78)
                        .lineLimit(2)
                        .frame(width: modeColumnWidths[index])
                        .frame(minHeight: 30)
                        .background(columnBackground(mode))
                }
            }
            .padding(.horizontal, 2)
            .frame(width: ResourceModeChoiceGeometry.controlWidth)
        }
        Divider().opacity(header ? 0.7 : 0.35)
    }

    private func columnBackground(_ mode: ResourceMode) -> Color {
        mode == selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.55) : .clear
    }
}

struct ProfilesSettingsSection: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Text(t("currentProfile"))
                Spacer(minLength: 12)
                Text(settings.matchingProfile?.name ?? t("customSettings"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(t("saveCurrentAsProfile")) { saveProfileWithPrompt() }
                    .buttonStyle(NMNeutralActionButtonStyle())
            }

            if settings.profiles.isEmpty {
                SettingsHelpText(t("profilesEmptyHelp"))
            } else {
                ForEach(settings.profiles) { profile in
                    profileRow(profile)
                }
            }
        } header: {
            SettingsSectionHeader(t("profiles"), help: t("profilesHelp"), helpLevel: .detail)
        }
    }

    private func profileRow(_ profile: NeManeemProfile) -> some View {
        let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(profile.name).font(.body.weight(.medium)).lineLimit(1)
                Spacer(minLength: 12)
                Button(t("apply")) { settings.applyProfile(id: profile.id) }
                    .buttonStyle(NMNeutralActionButtonStyle())
                Button(t("updateProfile")) { settings.updateProfile(id: profile.id) }
                    .buttonStyle(NMNeutralActionButtonStyle())
            }
            HStack(spacing: 8) {
                Toggle(t("showProfileInQuickLaunch"), isOn: Binding(
                    get: { settings.profiles.first(where: { $0.id == profile.id })?.showInQuickLaunch ?? false },
                    set: { enabled in
                        guard let i = settings.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
                        settings.profiles[i].showInQuickLaunch = enabled
                    }
                ))
                .toggleStyle(.checkbox)
                Spacer(minLength: 12)
                Button(role: .destructive) { settings.deleteProfile(id: profile.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(NMDestructiveIconButtonStyle())
                Button { settings.moveProfile(id: profile.id, offset: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(NMUtilityIconButtonStyle()).disabled(index == 0)
                Button { settings.moveProfile(id: profile.id, offset: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(NMUtilityIconButtonStyle()).disabled(index >= settings.profiles.count - 1)
            }
            SettingsHelpText(t("showProfileInQuickLaunchHelp"), level: .detail)
        }
        .padding(.vertical, 3)
    }

    private func saveProfileWithPrompt() {
        let alert = NSAlert()
        alert.messageText = t("saveCurrentAsProfile")
        alert.informativeText = t("profileNamePrompt")
        alert.addButton(withTitle: t("save"))
        alert.addButton(withTitle: t("cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = t("profileName")
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.saveCurrentProfile(name: field.stringValue, showInQuickLaunch: true)
    }
}

struct PermissionsSettingsSection: View {
    // Observe only the permission fields this section actually renders. The full
    // NetworkInterfaceMonitor also publishes live interface snapshots, and watching
    // the whole object made the General page rebuild on unrelated network updates.
    private let interface = AppEnvironment.shared.interfaceMonitor
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @AppStorage("language") private var languageRaw = AppLanguage.system.rawValue
    @State private var networkMonitoringAllowed = false
    @State private var locationServicesEnabled = CLLocationManager.locationServicesEnabled()
    @State private var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .system }
    private var t: (String) -> String { { L10n.text($0, language: language) } }

    var body: some View {
        Section(t("permissionManagement")) {
            permissionRow(title: t("networkMonitoringPermission"),
                          essentialDetail: nil,
                          detail: t("networkMonitoringPermissionPurpose"),
                          status: monitoringStatus,
                          actionTitle: monitoringActionTitle,
                          usesDestructiveSecondaryStyle: networkMonitoringAllowed) {
                if networkMonitoringAllowed || firewall.extensionNeedsUserApproval {
                    openNetworkExtensionSettings()
                } else if firewall.statusMessage != nil {
                    AppEnvironment.shared.requestSettingsSection?("troubleshooting")
                } else {
                    firewall.requestMonitoringPermission()
                }
            }
            if let message = firewall.statusMessage, !message.isEmpty {
                SettingsHelpText(message.localizedCaseInsensitiveContains("entitlement") ? t("signingRequired") : message)
            }
            permissionRow(title: t("wifiIdentityPermission"),
                          essentialDetail: t("wifiIdentityPermissionEssential"),
                          detail: t("wifiIdentityPermissionDetail"),
                          status: wifiStatus,
                          actionTitle: wifiActionTitle,
                          usesDestructiveSecondaryStyle: wiFiIdentityAuthorized) {
                if wiFiIdentityAuthorizationDenied || wiFiIdentityAuthorized || !locationServicesEnabled {
                    openLocationSettings()
                } else {
                    interface.requestWiFiIdentityAuthorization()
                }
            }
            SettingsHelpText(t("permissionManagementHelp"))
        }
        .onAppear {
            refreshPermissionState()
            interface.refreshWiFiIdentityAuthorizationStatus()
        }
        .onReceive(firewall.$engineIsEnabled.removeDuplicates()) { networkMonitoringAllowed = $0 }
        .onReceive(interface.$locationServicesEnabled.removeDuplicates()) { locationServicesEnabled = $0 }
        .onReceive(interface.$locationAuthorizationStatus.removeDuplicates()) { locationAuthorizationStatus = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
    }

    private var wiFiIdentityAuthorized: Bool {
        locationAuthorizationStatus != .notDetermined &&
        locationAuthorizationStatus != .denied &&
        locationAuthorizationStatus != .restricted
    }

    private var wiFiIdentityAuthorizationDenied: Bool {
        locationAuthorizationStatus == .denied || locationAuthorizationStatus == .restricted
    }

    private var wifiStatus: String {
        if !locationServicesEnabled { return t("locationServicesOff") }
        if wiFiIdentityAuthorized { return t("permissionAllowed") }
        if wiFiIdentityAuthorizationDenied { return t("permissionDenied") }
        return t("permissionNotRequested")
    }

    private var monitoringStatus: String {
        if networkMonitoringAllowed { return t("permissionAllowed") }
        if firewall.extensionNeedsUserApproval { return t("permissionApprovalPending") }
        if firewall.statusMessage != nil { return t("permissionNeedsAttention") }
        if firewall.isBusy { return t("permissionRequesting") }
        return t("permissionUnconfigured")
    }

    private var monitoringActionTitle: String? {
        if networkMonitoringAllowed { return t("openPermissionRemovalSettings") }
        if firewall.extensionNeedsUserApproval { return t("openSystemSettings") }
        if firewall.statusMessage != nil { return t("troubleshooting") }
        if firewall.isBusy { return nil }
        return t("requestPermission")
    }

    private var wifiActionTitle: String {
        if wiFiIdentityAuthorized { return t("openPermissionRemovalSettings") }
        if !locationServicesEnabled || wiFiIdentityAuthorizationDenied {
            return t("openSystemSettings")
        }
        return t("requestPermission")
    }

    private func refreshPermissionState() {
        networkMonitoringAllowed = firewall.engineIsEnabled
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        locationAuthorizationStatus = interface.locationAuthorizationStatus
    }

    private func permissionRow(title: String,
                               essentialDetail: String?,
                               detail: String?,
                               status: String,
                               actionTitle: String? = nil,
                               usesDestructiveSecondaryStyle: Bool = false,
                               actionDisabled: Bool = false,
                               action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let essentialDetail, !essentialDetail.isEmpty {
                        SettingsHelpText(essentialDetail)
                    }
                    if let detail, !detail.isEmpty {
                        SettingsHelpText(detail, level: .detail)
                    }
                }
                Spacer(minLength: 12)
                Text(status).font(.callout).foregroundStyle(.secondary)
                if let actionTitle, let action {
                    if usesDestructiveSecondaryStyle {
                        Button(actionTitle, action: action)
                            .buttonStyle(NMDestructiveSecondaryButtonStyle())
                            .disabled(actionDisabled)
                    } else {
                        Button(actionTitle, action: action)
                            .buttonStyle(NMNeutralActionButtonStyle())
                            .disabled(actionDisabled)
                    }
                }
            }
        }
    }

    /// Apple provides a stable API for the Login Items & Extensions parent page.
    /// Opening this known parent is preferable to a generic System Settings URL,
    /// which can reopen whichever pane happened to be visible last.
    private func openNetworkExtensionSettings() {
        SystemSettingsOpener.openNetworkExtensions()
    }

    private func openLocationSettings() {
        SystemSettingsOpener.openLocationServices()
    }
}

struct ExpertSettingsSection: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        Section(t("expertFeatures")) {
            Toggle(t("expertFeatures"), isOn: $settings.expertFeaturesEnabled)
            if settings.expertFeaturesEnabled && settings.resourceMode == .austerity {
                Label(t("expertSuspendedInAusterity"), systemImage: "leaf")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                SettingsHelpText(t("expertFeaturesHelp"))
            }

            VStack(alignment: .leading, spacing: 7) {
                expertFeatureRow(t("cmpSearchFilterSort"), location: t("expertLocationStatusWindows"))
                expertFeatureRow(t("cmpProcessDetails"), location: t("expertLocationProcessDetails"))
                expertFeatureRow(t("cmpCopyInfo"), location: t("expertLocationStatusWindows"))
                expertFeatureRow(t("cmpCSV"), location: t("expertLocationStatusWindows"))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private func expertFeatureRow(_ title: String, location: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("• \(title)")
            Spacer(minLength: 8)
            if settings.expertFeaturesEnabled && settings.resourceMode != .austerity {
                Text(location)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: settings.expertFeaturesEnabled)
    }
}

struct SettingsResetSheet: View {
    let t: (String) -> String
    let completion: (Bool) -> Void
    @State private var selected: Set<SettingsTransferSection> = []
    @State private var confirming = false

    private var choices: [SettingsTransferSection] {
        [.general, .menuBar, .statusWindows, .networkBehavior, .usagePreferences, .dataLimit]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("resetSettings"))
                .font(.title3.weight(.semibold))

            Toggle(t("selectAll"), isOn: allSelectedBinding)
                .toggleStyle(.checkbox)
                .font(.body.weight(.semibold))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(choices) { section in
                    Toggle(sectionTitle(section), isOn: sectionBinding(section))
                        .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            SettingsHelpText(t("resetSettingsDataSafeHelp"))

            HStack {
                Spacer()
                Button(t("cancel")) { completion(false) }
                    .buttonStyle(NMNeutralActionButtonStyle())
                Button(t("resetSelected"), role: .destructive) { confirming = true }
                    .buttonStyle(NMDestructiveActionButtonStyle())
                    .disabled(selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500)
        .confirmationDialog(t("confirmSettingsReset"), isPresented: $confirming, titleVisibility: .visible) {
            Button(t("resetSelected"), role: .destructive) {
                SettingsTransferService.resetSettings(sections: selected)
                if selected.contains(.general) {
                    AppEnvironment.shared.requestResetSettingsWindowSize?()
                }
                if selected.contains(.statusWindows) {
                    AppEnvironment.shared.requestResetMonitorWindowSize?()
                }
                completion(true)
            }
            Button(t("cancel"), role: .cancel) {}
        } message: {
            Text(t("resetSettingsDataSafeHelp"))
        }
    }

    private var allSelectedBinding: Binding<Bool> {
        Binding(
            get: { !choices.isEmpty && choices.allSatisfy { selected.contains($0) } },
            set: { enabled in
                if enabled { selected.formUnion(choices) }
                else { selected.subtract(choices) }
            }
        )
    }

    private func sectionBinding(_ section: SettingsTransferSection) -> Binding<Bool> {
        Binding(
            get: { selected.contains(section) },
            set: { enabled in
                if enabled { selected.insert(section) }
                else { selected.remove(section) }
            }
        )
    }

    private func sectionTitle(_ section: SettingsTransferSection) -> String {
        switch section {
        case .general: return t("backupGeneral")
        case .menuBar: return t("backupMenuBar")
        case .statusWindows: return t("backupStatusWindows")
        case .networkBehavior: return t("backupNetworkBehavior")
        case .usagePreferences: return t("backupUsagePreferences")
        case .dataLimit: return t("backupDataLimit")
        case .observedApps: return t("backupObservedApps")
        case .appPreferences: return t("backupAppPreferences")
        case .networkIdentifiers: return t("backupNetworkIdentifiers")
        }
    }
}
