import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct AppSelectionGroup: Identifiable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let icon: NSImage
    let members: [AppNetworkUsage]

    var memberIDs: [String] { Array(Set(members.map(\.id))).sorted() }
    var downloadBytesPerSecond: UInt64 { members.reduce(0) { $0 &+ $1.downloadBytesPerSecond } }
    var uploadBytesPerSecond: UInt64 { members.reduce(0) { $0 &+ $1.uploadBytesPerSecond } }
}

func appSelectionGroups(_ usages: [AppNetworkUsage]) -> [AppSelectionGroup] {
    Dictionary(grouping: usages, by: appSelectionKey).compactMap { key, members in
        guard let representative = members.sorted(by: { lhs, rhs in
            if lhs.isSystemProcess != rhs.isSystemProcess { return !lhs.isSystemProcess }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }).first else { return nil }
        return AppSelectionGroup(id: key,
                                 displayName: representative.appDisplayName ?? representative.displayName,
                                 bundleIdentifier: representative.bundleIdentifier,
                                 icon: representative.icon,
                                 members: members)
    }
}

func historicalAppSelectionGroup(identifier: String) -> AppSelectionGroup? {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
    let bundle = Bundle(url: appURL)
    let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? appURL.deletingPathExtension().lastPathComponent
    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
    icon.size = NSSize(width: 32, height: 32)
    return AppSelectionGroup(id: identifier,
                             displayName: name,
                             bundleIdentifier: identifier,
                             icon: icon,
                             members: [])
}

private enum AppRecommendationRange: Hashable {
    case last7
    case last30
    case custom
}

private struct AppRecommendationRow: Identifiable {
    enum Reason {
        case heavy
        case frequent
        case both
    }
    let id: String
    let group: AppSelectionGroup
    let totalBytes: UInt64
    let activeDays: Int
    let reason: Reason
}

struct ObservedAppSelectionEditor: View {
    @ObservedObject private var recorder = AppEnvironment.shared.usageRecorder
    @ObservedObject private var settings = AppEnvironment.shared.settings
    let usages: [AppNetworkUsage]
    @Binding var selectedIDs: [String]
    let t: (String) -> String
    @State private var searchText = ""
    @State private var recommendationRange: AppRecommendationRange = .last30
    @State private var recommendationStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var recommendationEnd = Date()
    @State private var showingRecommendations = false

    private var allGroups: [AppSelectionGroup] {
        appSelectionGroups(usages.filter { !$0.isSystemProcess })
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var candidates: [AppSelectionGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allGroups }
        return allGroups.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedGroupCount: Int {
        let selected = Set(selectedIDs)
        return allGroups.filter { group in
            selected.contains(group.id) || group.memberIDs.contains(where: selected.contains)
        }.count
    }

    private var recommendationBounds: (Date, Date) {
        let now = Date()
        switch recommendationRange {
        case .last7:
            return (Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now, now)
        case .last30:
            return (Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now, now)
        case .custom:
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: min(recommendationStart, recommendationEnd))
            let endDay = calendar.startOfDay(for: max(recommendationStart, recommendationEnd))
            let end = (calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay).addingTimeInterval(-1)
            return (start, min(end, now))
        }
    }

    private var recommendations: [AppRecommendationRow] {
        let bounds = recommendationBounds
        let stats = recorder.appRecommendationStats(from: bounds.0, to: bounds.1)
        guard !stats.isEmpty else { return [] }
        var groupsByID = Dictionary(uniqueKeysWithValues: allGroups.map { ($0.id, $0) })
        for stat in stats where groupsByID[stat.id] == nil {
            if let historical = historicalAppSelectionGroup(identifier: stat.id) {
                groupsByID[stat.id] = historical
            }
        }
        let valid = stats.filter { groupsByID[$0.id] != nil }
        let heavy = valid.sorted {
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.activeDays > $1.activeDays
        }
        let frequent = valid.sorted {
            if $0.activeDays != $1.activeDays { return $0.activeDays > $1.activeDays }
            return $0.totalBytes > $1.totalBytes
        }
        let heavyTop = Set(heavy.prefix(5).map(\.id))
        let frequentTop = Set(frequent.prefix(5).map(\.id))
        let ids = heavyTop.union(frequentTop)
        let statByID = Dictionary(uniqueKeysWithValues: valid.map { ($0.id, $0) })
        let heavyRank = Dictionary(uniqueKeysWithValues: heavy.enumerated().map { ($0.element.id, $0.offset) })
        let frequentRank = Dictionary(uniqueKeysWithValues: frequent.enumerated().map { ($0.element.id, $0.offset) })
        return ids.compactMap { id -> AppRecommendationRow? in
            guard let group = groupsByID[id], let stat = statByID[id] else { return nil }
            let reason: AppRecommendationRow.Reason
            if heavyTop.contains(id) && frequentTop.contains(id) { reason = .both }
            else if heavyTop.contains(id) { reason = .heavy }
            else { reason = .frequent }
            return AppRecommendationRow(id: id,
                                        group: group,
                                        totalBytes: stat.totalBytes,
                                        activeDays: stat.activeDays,
                                        reason: reason)
        }.sorted { lhs, rhs in
            let lhsRank = min(heavyRank[lhs.id] ?? 99, frequentRank[lhs.id] ?? 99)
            let rhsRank = min(heavyRank[rhs.id] ?? 99, frequentRank[rhs.id] ?? 99)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(t("appsToShow"))
                Spacer()
                Text("\(selectedGroupCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            TextField(t("searchApps"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if candidates.isEmpty {
                Text(t("noObservedApps"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(candidates) { group in
                            appRow(group)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            SettingsHelpText(t("appListGroupingHelp"))

            Button {
                showingRecommendations.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: showingRecommendations ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Label(t("recommendedApps"), systemImage: "sparkles")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showingRecommendations {
                VStack(alignment: .leading, spacing: 8) {
                    NMValueChoice(t("recommendationPeriod"), selection: $recommendationRange, options: [
                        (.last7, t("days7")),
                        (.last30, t("days30")),
                        (.custom, t("custom"))
                    ], controlWidth: naturalSegmentControlWidth([t("days7"), t("days30"), t("custom")]))
                    if recommendationRange == .custom {
                        HStack {
                            DatePicker(t("rangeStart"), selection: $recommendationStart, displayedComponents: [.date])
                                .nmNeutralValueControl()
                                .environment(\.locale, L10n.locale(for: settings.language))
                            DatePicker(t("rangeEnd"), selection: $recommendationEnd, displayedComponents: [.date])
                                .nmNeutralValueControl()
                                .environment(\.locale, L10n.locale(for: settings.language))
                        }
                    }

                    if recommendations.isEmpty {
                        SettingsHelpText(t("noAppRecommendations"))
                        if settings.recordingMode != .perApp {
                            SettingsHelpText(t("appRecommendationNeedsPerApp"))
                        }
                    } else {
                        ForEach(recommendations.prefix(8)) { item in
                            recommendationRow(item)
                        }
                    }
                    SettingsHelpText(t("appRecommendationsHelp"), level: .detail)
                }
                .padding(.top, 6)
            }
        }
    }

    private func appRow(_ group: AppSelectionGroup) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: group.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.displayName)
                    .lineLimit(1)
                if let bundle = group.bundleIdentifier {
                    Text(bundle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: selectionBinding(for: group))
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .padding(.vertical, 3)
    }

    private func recommendationRow(_ item: AppRecommendationRow) -> some View {
        let selected = isGroupSelected(item.group)
        return HStack(spacing: 8) {
            Image(nsImage: item.group.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.group.displayName)
                    .lineLimit(1)
                Text("\(recommendationReason(item.reason)) · \(SpeedFormatter.bytes(item.totalBytes)) · \(String(format: t("activeDaysFormat"), item.activeDays))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(selected ? t("selected") : t("addRecommendedApp")) {
                setGroup(item.group, selected: true)
            }
            .disabled(selected)
        }
        .padding(.vertical, 2)
    }

    private func recommendationReason(_ reason: AppRecommendationRow.Reason) -> String {
        switch reason {
        case .heavy: return t("heavyUse")
        case .frequent: return t("frequentUse")
        case .both: return t("frequentAndHeavy")
        }
    }

    private func isGroupSelected(_ group: AppSelectionGroup) -> Bool {
        let selected = Set(selectedIDs)
        return selected.contains(group.id) || group.memberIDs.contains(where: selected.contains)
    }

    private func selectionBinding(for group: AppSelectionGroup) -> Binding<Bool> {
        Binding(get: { isGroupSelected(group) }, set: { selected in
            setGroup(group, selected: selected)
        })
    }

    private func setGroup(_ group: AppSelectionGroup, selected: Bool) {
        var values = selectedIDs.filter { id in
            id != group.id && !group.memberIDs.contains(id)
        }
        if selected { values.append(group.id) }
        var seen = Set<String>()
        selectedIDs = values.filter { seen.insert($0).inserted }
    }
}
