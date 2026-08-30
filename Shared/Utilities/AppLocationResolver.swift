import AppKit
import Foundation

struct ResolvedAppLocation {
    let url: URL
    let isProcessSpecific: Bool
}

enum AppLocationResolver {
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

    @MainActor
    private static func url(forBundleIdentifier identifier: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == identifier }),
           let bundleURL = running.bundleURL {
            return bundleURL.resolvingSymlinksInPath()
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)?.resolvingSymlinksInPath()
    }
}
