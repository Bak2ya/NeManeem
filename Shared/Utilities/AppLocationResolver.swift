import AppKit
import Foundation

struct ResolvedAppLocation {
    let url: URL
    let isProcessSpecific: Bool
}

struct ParentAppCandidate: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    var id: String { bundleIdentifier }
}

enum AppLocationResolver {
    // Bundle-location lookups are stable for the lifetime of the app and can be
    // surprisingly expensive when repeated for every row in a large app list.
    // Cache both hits and misses so app identity actions stay lazy and cheap.
    @MainActor private static var applicationURLCache: [String: URL] = [:]
    @MainActor private static var missingApplicationURLs: Set<String> = []
    @MainActor
    static func resolve(_ usage: AppNetworkUsage, preferProcess: Bool) -> ResolvedAppLocation? {
        if preferProcess,
           let processIdentifier = usage.processIdentifier,
           !processIdentifier.isEmpty,
           let url = url(forBundleIdentifier: processIdentifier) {
            return ResolvedAppLocation(url: url, isProcessSpecific: true)
        }
        if let bundleIdentifier = usage.bundleIdentifier,
           !bundleIdentifier.isEmpty,
           let url = url(forBundleIdentifier: bundleIdentifier) {
            return ResolvedAppLocation(url: url, isProcessSpecific: false)
        }
        return nil
    }

    @MainActor
    static func reveal(_ location: ResolvedAppLocation) {
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    /// Candidate owners are deliberately limited to application identities already
    /// observed by NeManeem. Candidate construction itself does not scan the file
    /// system or require an additional entitlement; file lookup stays user-invoked.
    @MainActor
    static func parentAppCandidates(from usages: [AppNetworkUsage], excluding usage: AppNetworkUsage) -> [ParentAppCandidate] {
        var values: [String: ParentAppCandidate] = [:]
        for candidate in usages {
            guard !candidate.isSystemProcess,
                  let bundleIdentifier = candidate.bundleIdentifier,
                  !bundleIdentifier.isEmpty,
                  !bundleIdentifier.hasPrefix("com.bak2ya.NeManeem"),
                  bundleIdentifier != usage.bundleIdentifier else { continue }
            let name = candidate.appDisplayName ?? candidate.displayName
            let existing = values[bundleIdentifier]
            if existing == nil || name.localizedCaseInsensitiveCompare(existing!.displayName) == .orderedAscending {
                values[bundleIdentifier] = ParentAppCandidate(bundleIdentifier: bundleIdentifier, displayName: name)
            }
        }
        return values.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    @MainActor
    static func canManuallyGroup(_ usage: AppNetworkUsage) -> Bool {
        if let process = usage.processIdentifier, !process.isEmpty {
            return process != usage.bundleIdentifier
        }
        return usage.isSystemProcess && !usage.id.isEmpty && !usage.id.hasPrefix("system-display:")
    }

    /// Present transparent local identity information instead of claiming that an
    /// out-of-bundle helper always belongs to a specific app. A verified source-app
    /// identity is distinguished from a user-created display grouping.
    @MainActor
    static func showInformation(for usage: AppNetworkUsage,
                                manualParentBundle: String?,
                                language: AppLanguage) {
        let t: (String) -> String = { L10n.text($0, language: language) }
        let bundleIdentifier = usage.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let processIdentifier = usage.processIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentName: String
        let basis: String

        if let manualParentBundle, !manualParentBundle.isEmpty {
            parentName = applicationDisplayName(bundleIdentifier: manualParentBundle) ?? usage.appDisplayName ?? usage.displayName
            basis = t("ownershipBasisManual")
        } else if let bundleIdentifier, !bundleIdentifier.isEmpty {
            parentName = applicationDisplayName(bundleIdentifier: bundleIdentifier) ?? usage.appDisplayName ?? usage.displayName
            if let processIdentifier, !processIdentifier.isEmpty, processIdentifier != bundleIdentifier {
                basis = t("ownershipBasisVerified")
            } else {
                basis = t("ownershipBasisDirect")
            }
        } else {
            parentName = t("parentAppNotVerified")
            basis = t("ownershipBasisUnknown")
        }

        var lines: [String] = [
            "\(t("applicationName")): \(usage.displayName)",
            "\(t("parentApp")): \(parentName)"
        ]
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            lines.append("\(t("bundleIdentifier")): \(bundleIdentifier)")
        }
        if let processIdentifier, !processIdentifier.isEmpty, processIdentifier != bundleIdentifier {
            lines.append("\(t("processIdentifier")): \(processIdentifier)")
        }
        if let location = resolve(usage, preferProcess: false) {
            lines.append("\(t("applicationPath")): \(location.url.path)")
        }
        lines.append("")
        lines.append("\(t("ownershipBasis")): \(basis)")
        if manualParentBundle != nil {
            lines.append(t("manualGroupingHelp"))
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = t("appInformation")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: t("ok"))
        alert.runModal()
    }

    @MainActor
    private static func applicationDisplayName(bundleIdentifier: String) -> String? {
        guard let appURL = url(forBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: appURL) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    @MainActor
    private static func url(forBundleIdentifier identifier: String) -> URL? {
        if let cached = applicationURLCache[identifier] { return cached }
        if missingApplicationURLs.contains(identifier) { return nil }

        let resolved: URL?
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == identifier }),
           let bundleURL = running.bundleURL {
            resolved = bundleURL.resolvingSymlinksInPath()
        } else {
            resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)?.resolvingSymlinksInPath()
        }

        if let resolved {
            applicationURLCache[identifier] = resolved
            return resolved
        }
        missingApplicationURLs.insert(identifier)
        return nil
    }
}
