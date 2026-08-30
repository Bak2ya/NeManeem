import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
        if status != .requiresApproval {
            errorMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Explicit removal path used by the in-app safe uninstall guide.
    /// Returning the error lets the guide report the real result instead of
    /// showing a success check mark when macOS refused the change.
    func disableForRemoval() -> Error? {
        refresh()
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
            refresh()
            return nil
        } catch {
            errorMessage = error.localizedDescription
            refresh()
            return error
        }
    }
}
