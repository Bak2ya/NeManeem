import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum MainSection: String, CaseIterable, Identifiable {
    case general, interface, network
    case usage = "statistics" // Preserve the persisted raw value from pre-0.5.36 builds.
    case dataLimit, troubleshooting, about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .general: return "general"
        case .interface: return "interfaceSettings"
        case .network: return "network"
        case .usage: return "usage"
        case .dataLimit: return "limitManagement"
        case .troubleshooting: return "troubleshooting"
        case .about: return "about"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .interface: return "menubar.rectangle"
        case .network: return "network"
        case .usage: return "chart.bar.xaxis"
        case .dataLimit: return "gauge"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}

private enum InterfacePage: String {
    case root, menuBar, popover, monitor
}

private struct SettingsSearchItem: Identifiable {
    let id: String
    let title: String
    let path: String
    let keywords: [String]
    let section: MainSection
    let interfacePage: InterfacePage?
    let highlight: String?

    func matches(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return false }
        return ([title, path] + keywords).contains { $0.lowercased().contains(query) }
    }
}

struct SettingsHighlightBackground: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.vertical, active ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color.accentColor.opacity(0.14) : .clear)
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
    }
}


private struct MacSettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = true
        field.delegate = context.coordinator
        field.focusRingType = .default
        field.controlSize = .regular
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

struct MainWindowView: View {
    // The settings shell observes only values that affect navigation/appearance.
    // Individual pages still own their SettingsStore observations so changing one
    // option does not invalidate the entire settings hierarchy.
    private let environment = AppEnvironment.shared
    @AppStorage("main.lastSection") private var selectionRaw = MainSection.general.rawValue
    @AppStorage("language") private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("appearance.accentMode") private var accentModeRaw = AppAccentMode.system.rawValue
    @AppStorage("appearance.customAccentHex") private var customAccentHex = NeManeemTheme.defaultCustomAccentHex
    @State private var preferredReadingScale: CGFloat = 1.0
    @State private var interfacePage: InterfacePage = .root
    @State private var searchText = ""
    @State private var highlightedSetting: String?

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .system }
    private var usesLargeAccessibilityText: Bool { preferredReadingScale > 1.08 }
    private var sidebarWidth: CGFloat { usesLargeAccessibilityText ? 208 : 178 }
    private var preferredBodyFont: Font { Font(NSFont.preferredFont(forTextStyle: .body)) }
    private var t: (String) -> String { { L10n.text($0, language: language) } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                    .frame(minWidth: sidebarWidth, maxWidth: sidebarWidth, maxHeight: .infinity, alignment: .top)

                Divider()

                detailColumn
                    .id("\(selection.rawValue)-\(interfacePage.rawValue)")
                    .headerProminence(.increased)
                    .font(preferredBodyFont)
                    .controlSize(usesLargeAccessibilityText ? .large : .regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        // Date/time controls follow the Mac's region format even when NeManeem's
        // UI language is selected independently.
        .environment(\.locale, Locale.autoupdatingCurrent)
        // Stateful controls inherit the accent. Ordinary Buttons inherit the neutral
        // action rule unless a closer primary/destructive/navigation style overrides it.
        .tint(shellAccent)
        .buttonStyle(NMNeutralActionButtonStyle())
        .onAppear {
            applyRequestedDestination(environment.requestedSettingsDestination)
            refreshPreferredReadingScale()
            syncInterfacePreview()
        }
        .onChange(of: interfacePage) { _ in syncInterfacePreview() }
        .onChange(of: selectionRaw) { _ in syncInterfacePreview() }
        .onChange(of: usesLargeAccessibilityText) { largeText in
            environment.requestSettingsAccessibilityLayout?(largeText)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPreferredReadingScale()
        }
        .onReceive(environment.$requestedSettingsDestination) { destination in
            applyRequestedDestination(destination)
            syncInterfacePreview()
        }
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let childTitle = interfaceChildTitle {
                Text(childTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.bottom, 2)
            }
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    private var interfaceChildTitle: String? {
        guard selection == .interface else { return nil }
        switch interfacePage {
        case .root: return nil
        case .menuBar: return t("menubar")
        case .popover: return t("popover")
        case .monitor: return t("monitorWindow")
        }
    }

    private func syncInterfacePreview() {
        let previewPage = selection == .interface ? interfacePage : .root
        let wantsPopover = previewPage == .popover
        let wantsMonitor = previewPage == .monitor

        if environment.popoverPreviewVisible != wantsPopover {
            environment.popoverPreviewVisible = wantsPopover
            environment.requestPopoverPreview?(wantsPopover)
        }
        if environment.monitorPreviewVisible != wantsMonitor {
            environment.monitorPreviewVisible = wantsMonitor
            environment.requestMonitorPreview?(wantsMonitor)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Leave only the physical traffic-light area clear. Unlike earlier
            // builds this does not create a matching blank title row in the detail
            // column; the right side can use that vertical space immediately.
            MacSettingsSearchField(text: $searchText, placeholder: t("searchSettings"))
                .frame(height: usesLargeAccessibilityText ? 30 : 26)
                .padding(.top, usesLargeAccessibilityText ? 44 : 40)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                List(selection: selectionBinding) {
                    ForEach(MainSection.allCases) { section in
                        Label(title(section), systemImage: section.icon).tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                searchResults
            }

            Spacer(minLength: 8)
        }
        .background(.thinMaterial)
        // Child-page navigation belongs to the same left chrome as the traffic
        // lights rather than to the detail content. Keeping it structurally inside
        // the sidebar chrome also makes its position independent of page layout.
        .overlay(alignment: .topTrailing) {
            if selection == .interface && interfacePage != .root {
                Button {
                    interfacePage = .root
                    highlightedSetting = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(NMNavigationButtonStyle())
                .help(t("back"))
                // The signal lights stay at the leading edge. The back button is
                // anchored to the trailing edge of the same floating chrome, leaving
                // the middle area available for safe window dragging.
                .padding(.trailing, 10)
                .padding(.top, 4)
            }
        }
    }

    private var searchResults: some View {
        let results = searchItems.filter { $0.matches(searchText) }
        return ScrollView {
            LazyVStack(spacing: 2) {
                if results.isEmpty {
                    Text(t("noSettingsSearchResults"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ForEach(results.prefix(24)) { item in
                        Button {
                            openSearchResult(item)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text(item.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func refreshPreferredReadingScale() {
        let normal = max(1, NSFont.systemFontSize)
        let preferred = NSFont.preferredFont(forTextStyle: .body).pointSize
        preferredReadingScale = max(1.0, preferred / normal)
        environment.requestSettingsAccessibilityLayout?(preferredReadingScale > 1.08)
    }

    private var shellAccent: Color {
        switch AppAccentMode(rawValue: accentModeRaw) ?? .system {
        case .system: return Color(nsColor: .controlAccentColor)
        case .neutral: return Color(nsColor: .systemGray)
        case .custom:
            return Color(nsColor: NeManeemTheme.nsColor(fromHex: customAccentHex)
                         ?? NeManeemTheme.nsColor(fromHex: NeManeemTheme.defaultCustomAccentHex)!)
        }
    }

    private var selection: MainSection { MainSection(rawValue: selectionRaw) ?? .general }

    private var selectionBinding: Binding<MainSection> {
        Binding(get: { selection }, set: { newValue in
            selectionRaw = newValue.rawValue
            if newValue != .interface { interfacePage = .root }
            highlightedSetting = nil
        })
    }

    private func applyRequestedDestination(_ raw: String?) {
        guard let raw else { return }
        switch raw {
        case "menuBar", "interface-menuBar":
            selectionRaw = MainSection.interface.rawValue
            interfacePage = .menuBar
        case "popover", "interface-popover":
            selectionRaw = MainSection.interface.rawValue
            interfacePage = .popover
        case "popover-monitor", "interface-monitor":
            selectionRaw = MainSection.interface.rawValue
            interfacePage = .monitor
        case "usage":
            // Visible-name alias for callers added after the refactor. The stored
            // raw value remains `statistics` so existing users keep their selection.
            selectionRaw = MainSection.usage.rawValue
            interfacePage = .root
        case "network-local":
            selectionRaw = MainSection.network.rawValue
            interfacePage = .root
            highlightedSetting = "local"
        case "general-permissions":
            selectionRaw = MainSection.general.rawValue
            interfacePage = .root
            highlightedSetting = "permissions"
        case "dataLimit-current":
            selectionRaw = MainSection.dataLimit.rawValue
            interfacePage = .root
            highlightedSetting = "current"
        default:
            if let section = MainSection(rawValue: raw) {
                selectionRaw = section.rawValue
                interfacePage = .root
            }
        }
    }

    private func title(_ section: MainSection) -> String {
        t(section.titleKey)
    }

    @ViewBuilder private var detailView: some View {
        switch selection {
        case .general: GeneralSettingsView(highlight: highlightedSetting)
        case .interface:
            switch interfacePage {
            case .root: InterfaceSettingsHome(open: { interfacePage = $0 })
            case .menuBar: MenuBarSettingsView(highlight: highlightedSetting)
            case .popover: PopoverSettingsView(surface: .popover, highlight: highlightedSetting)
            case .monitor: PopoverSettingsView(surface: .monitor, highlight: highlightedSetting)
            }
        case .network: NetworkSettingsView(highlight: highlightedSetting)
        case .usage: UsageSettingsView(highlight: highlightedSetting)
        case .dataLimit: DataLimitSettingsView(highlight: highlightedSetting)
        case .troubleshooting: TroubleshootingSettingsView()
        case .about: AboutSettingsView()
        }
    }

    private func openSearchResult(_ item: SettingsSearchItem) {
        selectionRaw = item.section.rawValue
        interfacePage = item.interfacePage ?? .root
        searchText = ""
        highlightedSetting = item.highlight
        guard item.highlight != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if highlightedSetting == item.highlight { highlightedSetting = nil }
        }
    }

    private var searchItems: [SettingsSearchItem] {
        [
            // General
            .init(id: "general-login", title: t("launchAtLogin"), path: t("general"), keywords: ["login", "startup", "자동 실행"], section: .general, interfacePage: nil, highlight: "general"),
            .init(id: "general-appearance", title: t("appearance"), path: t("general"), keywords: ["dark", "light", "화면", "다크", "라이트"], section: .general, interfacePage: nil, highlight: "general"),
            .init(id: "general-accent", title: t("accentColor"), path: t("general"), keywords: ["color", "색상", "강조"], section: .general, interfacePage: nil, highlight: "general"),
            .init(id: "general-language", title: t("language"), path: t("general"), keywords: ["language", "언어", "한국어", "english"], section: .general, interfacePage: nil, highlight: "general"),
            .init(id: "general-detailed-descriptions", title: t("detailedDescriptions"), path: t("general"), keywords: ["설명", "상세", "detail", "description"], section: .general, interfacePage: nil, highlight: "general"),
            .init(id: "general-window-size", title: t("settingsWindowSize"), path: t("general"), keywords: ["window", "size", "설정창", "크기"], section: .general, interfacePage: nil, highlight: "general"),
            .init(id: "general-resource", title: t("resourceModeTitle"), path: t("general"), keywords: ["긴축", "절전", "균형", "성능", "resource"], section: .general, interfacePage: nil, highlight: "resource"),
            .init(id: "general-profile", title: t("profiles"), path: t("general"), keywords: ["profile", "프로필", "집", "외출"], section: .general, interfacePage: nil, highlight: "profiles"),
            .init(id: "general-permission", title: t("permissionManagement"), path: t("general"), keywords: ["permission", "권한", "ssid", "wifi", "위치"], section: .general, interfacePage: nil, highlight: "permissions"),
            .init(id: "general-export", title: t("exportSettings"), path: t("general"), keywords: ["backup", "export", "백업", "내보내기", "가져오기"], section: .general, interfacePage: nil, highlight: "data"),
            .init(id: "general-remove", title: t("safeRemovalTitle"), path: t("general"), keywords: ["delete", "remove", "삭제", "제거", "휴지통"], section: .general, interfacePage: nil, highlight: "remove"),
            .init(id: "general-expert", title: t("expertFeatures"), path: t("general"), keywords: ["expert", "advanced", "전문가", "고급"], section: .general, interfacePage: nil, highlight: "expert"),

            // Interface root and Menu Bar
            .init(id: "interface-menu", title: t("menubar"), path: t("interfaceSettings"), keywords: ["menu", "메뉴바"], section: .interface, interfacePage: .menuBar, highlight: nil),
            .init(id: "interface-popover", title: t("popover"), path: t("interfaceSettings"), keywords: ["popover", "팝오버"], section: .interface, interfacePage: .popover, highlight: nil),
            .init(id: "interface-monitor", title: t("monitorWindow"), path: t("interfaceSettings"), keywords: ["monitor", "모니터", "창"], section: .interface, interfacePage: .monitor, highlight: nil),
            .init(id: "menu-layout", title: t("menuBarLayout"), path: "\(t("interfaceSettings")) › \(t("menubar"))", keywords: ["menu", "메뉴바", "arrow", "화살표", "한도", "layout", "배치"], section: .interface, interfacePage: .menuBar, highlight: "layout"),
            .init(id: "menu-size", title: t("displaySize"), path: "\(t("interfaceSettings")) › \(t("menubar"))", keywords: ["font", "size", "크기", "글자", "포인트"], section: .interface, interfacePage: .menuBar, highlight: "appearance"),
            .init(id: "menu-unit", title: t("unit"), path: "\(t("interfaceSettings")) › \(t("menubar"))", keywords: ["unit", "단위", "kb", "mb", "bit"], section: .interface, interfacePage: .menuBar, highlight: "appearance"),
            .init(id: "menu-refresh", title: t("networkSpeedRefreshInterval"), path: "\(t("interfaceSettings")) › \(t("menubar"))", keywords: ["refresh", "반영", "주기", "속도"], section: .interface, interfacePage: .menuBar, highlight: "refresh"),
            .init(id: "menu-advanced", title: t("advanced"), path: "\(t("interfaceSettings")) › \(t("menubar"))", keywords: ["font", "gap", "spacing", "고급", "글꼴", "간격"], section: .interface, interfacePage: .menuBar, highlight: "advanced"),

            // Popover / Monitor
            .init(id: "popover-columns", title: t("columnLayout"), path: "\(t("interfaceSettings")) › \(t("popover"))", keywords: ["column", "열", "download", "upload", "배치"], section: .interface, interfacePage: .popover, highlight: "content"),
            .init(id: "popover-limit", title: t("displayLocationLimit"), path: "\(t("interfaceSettings")) › \(t("popover"))", keywords: ["한도", "세션", "표시 항목"], section: .interface, interfacePage: .popover, highlight: "content"),
            .init(id: "popover-size", title: t("displaySize"), path: "\(t("interfaceSettings")) › \(t("popover"))", keywords: ["font", "size", "크기", "글자", "포인트"], section: .interface, interfacePage: .popover, highlight: "appearance"),
            .init(id: "popover-refresh", title: t("networkSpeedRefreshInterval"), path: "\(t("interfaceSettings")) › \(t("popover"))", keywords: ["refresh", "반영", "주기", "속도"], section: .interface, interfacePage: .popover, highlight: "refresh"),
            .init(id: "popover-window", title: t("windowBehavior"), path: "\(t("interfaceSettings")) › \(t("popover"))", keywords: ["window", "창", "숨기기", "비활성"], section: .interface, interfacePage: .popover, highlight: "window"),
            .init(id: "popover-advanced", title: t("advanced"), path: "\(t("interfaceSettings")) › \(t("popover"))", keywords: ["advanced", "고급", "process", "프로세스", "정렬"], section: .interface, interfacePage: .popover, highlight: "advanced"),
            .init(id: "monitor-settings", title: t("monitorIndividualSettings"), path: "\(t("interfaceSettings")) › \(t("monitorWindow"))", keywords: ["monitor", "모니터", "개별", "팝오버 설정"], section: .interface, interfacePage: .monitor, highlight: "inherit"),
            .init(id: "monitor-size", title: t("displaySize"), path: "\(t("interfaceSettings")) › \(t("monitorWindow"))", keywords: ["size", "크기", "글자", "포인트"], section: .interface, interfacePage: .monitor, highlight: "appearance"),
            .init(id: "monitor-refresh", title: t("networkSpeedRefreshInterval"), path: "\(t("interfaceSettings")) › \(t("monitorWindow"))", keywords: ["refresh", "반영", "주기", "속도"], section: .interface, interfacePage: .monitor, highlight: "refresh"),

            // Network
            .init(id: "network-local", title: t("separateLocalTraffic"), path: t("network"), keywords: ["nas", "local", "로컬", "내부 네트워크", "분리"], section: .network, interfacePage: nil, highlight: "local"),
            .init(id: "network-scope", title: t("menuBarScope"), path: t("network"), keywords: ["로컬 네트워크 제외", "모두", "메뉴바", "포함 범위"], section: .network, interfacePage: nil, highlight: "local"),
            .init(id: "network-safari", title: t("safariNetworkServiceGrouping"), path: t("network"), keywords: ["safari", "webkit"], section: .network, interfacePage: nil, highlight: "control"),
            .init(id: "network-control", title: t("networkControl"), path: t("network"), keywords: ["filter", "차단", "허용", "앱별", "네트워크 제어"], section: .network, interfacePage: nil, highlight: "control"),

            // Usage
            .init(id: "usage-recording", title: t("usageRecording"), path: t("usage"), keywords: ["record", "history", "기록", "저장"], section: .usage, interfacePage: nil, highlight: "recording"),
            .init(id: "usage-session", title: t("sessionRecording"), path: t("usage"), keywords: ["session", "세션", "스톱워치", "측정"], section: .usage, interfacePage: nil, highlight: "session"),
            .init(id: "usage-period", title: t("displayPeriod"), path: t("usage"), keywords: ["오늘", "7일", "30일", "전체", "기간", "월"], section: .usage, interfacePage: nil, highlight: "usage"),
            .init(id: "usage-export", title: t("dataManagement"), path: t("usage"), keywords: ["excel", "xlsx", "csv", "내보내기", "요약", "삭제"], section: .usage, interfacePage: nil, highlight: "data"),

            // Data limit
            .init(id: "limit-amount", title: t("dataLimitSettings"), path: t("limitManagement"), keywords: ["limit", "한도", "현재", "표시 방식", "표시 위치"], section: .dataLimit, interfacePage: nil, highlight: "limit"),
            .init(id: "limit-network", title: t("limitApplicationSection"), path: t("limitManagement"), keywords: ["network", "ssid", "인터넷만", "모두", "소모 기준", "적용 네트워크"], section: .dataLimit, interfacePage: nil, highlight: "application"),
            .init(id: "limit-period", title: t("limitManagementPeriodSection"), path: t("limitManagement"), keywords: ["기간", "시작", "종료", "월별", "주기", "선택월 말일"], section: .dataLimit, interfacePage: nil, highlight: "period"),
            .init(id: "limit-alert", title: t("dataLimitWarning"), path: t("limitManagement"), keywords: ["warning", "알림", "경고", "차단"], section: .dataLimit, interfacePage: nil, highlight: "alerts")
        ]
    }
}

private struct InterfaceSettingsHome: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let open: (InterfacePage) -> Void
    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    var body: some View {
        Form {
            Section {
                interfaceRow(icon: "menubar.rectangle", title: t("menubar"), help: t("menuBarInterfaceHelp")) { open(.menuBar) }
                interfaceRow(icon: "rectangle.topthird.inset.filled", title: t("popover"), help: t("popoverDescription")) { open(.popover) }
                interfaceRow(icon: "macwindow", title: t("monitorWindow"), help: t("monitorInterfaceHelp")) { open(.monitor) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func interfaceRow(icon: String, title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(help).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

