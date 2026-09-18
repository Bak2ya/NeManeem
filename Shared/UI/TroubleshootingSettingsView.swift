import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct TroubleshootingSettingsView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @ObservedObject private var firewall = AppEnvironment.shared.firewallController
    @ObservedObject private var traffic = AppEnvironment.shared.appTrafficMonitor
    @ObservedObject private var interface = AppEnvironment.shared.interfaceMonitor
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @StateObject private var diagnostics = TroubleshootingService()
    @State private var showingReportWarning = false
    @State private var showingMailUnavailable = false
    @State private var diagnosticAIConsent = false

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        VStack(spacing: 0) {

            Form {
                Section {
                    SettingsHelpText(t("diagnosticIntro"))
                    HStack {
                        Button {
                            Task { await diagnostics.runDiagnosis(firewall: firewall, traffic: traffic, interface: interface, knownNetworkCount: recorder.knownNetworks.count) }
                        } label: {
                            if diagnostics.isDiagnosing {
                                HStack(spacing: 7) {
                                    ProgressView().controlSize(.small)
                                    Text(diagnostics.isCheckingMeasurementEngine ? t("checkingMeasurementEngine") : t("diagnosing"))
                                }
                            } else {
                                Label(diagnostics.snapshot == nil ? t("startDiagnosis") : t("rerunDiagnosis"),
                                      systemImage: "stethoscope")
                            }
                        }
                        .buttonStyle(NMPrimaryActionButtonStyle())
                        .controlSize(.regular)
                        .disabled(diagnostics.isDiagnosing || diagnostics.isGeneratingReport)
                        Spacer()
                        Text(t("diagnosticNoChanges"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let snapshot = diagnostics.snapshot {
                    Section(t("diagnosticChecklist")) {
                        diagnosticRow(
                            title: t("appLocation"),
                            systemImage: snapshot.appIsInApplications ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            detail: snapshot.appIsInApplications ? t("appLocationOK") : t("appLocationProblem")
                        ) {
                            if !snapshot.appIsInApplications {
                                SettingsHelpText(t("appLocationFix"))
                                HStack {
                                    Button(t("openCurrentLocation")) { diagnostics.openCurrentAppLocation() }
                                    Button(t("openApplicationsFolder")) { diagnostics.openApplicationsFolder() }
                                }
                            }
                        }

                        diagnosticRow(
                            title: t("networkExtension"),
                            systemImage: snapshot.filterConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            detail: snapshot.filterConfigured ? t("networkExtensionOK") : t("networkExtensionProblem")
                        ) {
                            if !snapshot.filterConfigured || snapshot.extensionNeedsUserApproval {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 10) {
                                        Image(nsImage: NSApplication.shared.applicationIconImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 32, height: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("NeManeem")
                                                .font(.callout.weight(.semibold))
                                            Text(t("networkExtensionIdentityHelp"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    (Text(t("networkExtensionFixPrefix")) + Text(t("networkExtensionFixEmphasis")).bold() + Text(t("networkExtensionFixSuffix")))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    (Text(t("networkExtensionCategoryPrefix")) + Text(t("networkExtensionCategoryEmphasis")).bold() + Text(t("networkExtensionCategorySuffix")))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    SettingsHelpText(t("networkExtensionReconfigurationHelp"))
                                }
                                HStack {
                                    Button(t("requestNetworkPermissionAgain")) {
                                        firewall.requestMonitoringPermission()
                                    }
                                    .disabled(firewall.isBusy)
                                    Button(t("openSystemSettings")) {
                                        SMAppService.openSystemSettingsLoginItems()
                                    }
                                }
                            }
                        }

                        diagnosticRow(
                            title: t("measurementEngine"),
                            systemImage: snapshot.trafficConnected ? "checkmark.circle.fill" : "xmark.circle.fill",
                            detail: snapshot.trafficConnected ? t("measurementEngineOK") : t("measurementEngineProblem")
                        ) {
                            if !snapshot.trafficConnected, snapshot.connectionFailureCount > 0 {
                                Text("\(t("connectionFailures")): \(snapshot.connectionFailureCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section(t("optionalFeatures")) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t("wifiIdentityPermission"))
                                SettingsHelpText(t("wifiIdentityPermissionPurpose"))
                                SettingsHelpText(t("wifiIdentityPermissionDetail"), level: .detail)
                                SettingsHelpText(t("wifiIdentityPermissionEssential"))
                            }
                            Spacer(minLength: 12)
                            Text(troubleshootingWiFiStatus)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let actionTitle = troubleshootingWiFiActionTitle {
                                Button(actionTitle) { performTroubleshootingWiFiAction() }
                                    .buttonStyle(NMNeutralActionButtonStyle())
                            }
                        }
                    }

                    Section(t("diagnosticReport")) {
                        SettingsHelpText(t("diagnosticReportHelp"))
                        Button {
                            showingReportWarning = true
                        } label: {
                            Label(t("sendDiagnostics"), systemImage: "envelope.badge")
                        }
                        .disabled(diagnostics.isGeneratingReport)

                        if diagnostics.isGeneratingReport {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(t("creatingReport")).foregroundStyle(.secondary)
                            }
                        }

                        if let report = diagnostics.report {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(t("reportCreatedTitle"))
                                    .font(.callout.weight(.semibold))
                                Text(t("reportCreatedHint"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Toggle(t("diagnosticAIConsent"), isOn: $diagnosticAIConsent)
                                    .toggleStyle(.checkbox)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack {
                                    Button(t("viewReport")) { diagnostics.openReport() }
                                    Button(t("sendByEmail")) {
                                        if !diagnostics.composeEmail() {
                                            showingMailUnavailable = true
                                        }
                                    }
                                    .disabled(!diagnosticAIConsent)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("SHA-256")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(report.sha256)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                SettingsHelpText(t("reportIntegrityHelp"))
                            }
                            .padding(.top, 4)
                        }

                        if let error = diagnostics.errorMessage {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        }
        .onAppear { interface.refreshWiFiIdentityAuthorizationStatus() }
        .alert(t("diagnosticReportWarningTitle"), isPresented: $showingReportWarning) {
            Button(t("cancel"), role: .cancel) { }
            Button(t("createReport")) {
                diagnosticAIConsent = false
                Task { await diagnostics.generateReport(firewall: firewall, traffic: traffic, interface: interface, knownNetworkCount: recorder.knownNetworks.count) }
            }
        } message: {
            Text(t("diagnosticReportWarningBody"))
        }
        .alert(t("mailUnavailableTitle"), isPresented: $showingMailUnavailable) {
            Button(t("ok"), role: .cancel) { }
        } message: {
            Text(t("mailUnavailableBody"))
        }
    }

    private var troubleshootingWiFiStatus: String {
        if !interface.locationServicesEnabled { return t("locationServicesOff") }
        if interface.wiFiIdentityAuthorized { return t("permissionAllowed") }
        if interface.wiFiIdentityAuthorizationDenied { return t("permissionDenied") }
        return t("permissionNotRequested")
    }

    private var troubleshootingWiFiActionTitle: String? {
        if interface.wiFiIdentityAuthorized { return nil }
        if !interface.locationServicesEnabled || interface.wiFiIdentityAuthorizationDenied {
            return t("openSystemSettings")
        }
        return t("requestPermission")
    }

    private func performTroubleshootingWiFiAction() {
        if !interface.locationServicesEnabled || interface.wiFiIdentityAuthorizationDenied {
            SystemSettingsOpener.openLocationServices()
        } else {
            interface.requestWiFiIdentityAuthorization()
        }
    }

    @ViewBuilder
    private func diagnosticRow<Content: View>(title: String,
                                              systemImage: String,
                                              detail: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
                .padding(.leading, 24)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings 7. About

