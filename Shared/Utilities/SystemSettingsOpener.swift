import AppKit
import ServiceManagement

enum SystemSettingsOpener {
    static func openNetworkExtensions() {
        // Apple provides a stable entry point for Login Items & Extensions.
        SMAppService.openSystemSettingsLoginItems()
    }

    static func openLocationServices() {
        // macOS has used more than one Settings URL across releases. Prefer the
        // long-standing Privacy_LocationServices anchor first; newer aliases are
        // fallbacks. If none are accepted, open Privacy & Security rather than an
        // unrelated last-viewed Settings pane.
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }
}
