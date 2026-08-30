import AppKit
import SwiftUI

enum NeManeemTheme {
    static let defaultCustomAccentHex = "#3F6FA8"

    /// Compatibility accessor for small reusable subviews that do not own a
    /// SettingsStore observation. Parent settings views already redraw when the
    /// shared store changes, so reading the persisted semantic mode here keeps all
    /// selection chrome in sync without threading a color argument through every
    /// editor component.
    static var accent: Color {
        let defaults = UserDefaults.standard
        let mode = AppAccentMode(rawValue: defaults.string(forKey: "appearance.accentMode") ?? "") ?? .system
        switch mode {
        case .system:
            return Color(nsColor: .controlAccentColor)
        case .neutral:
            return Color(nsColor: .systemGray)
        case .custom:
            let hex = defaults.string(forKey: "appearance.customAccentHex") ?? defaultCustomAccentHex
            return Color(nsColor: nsColor(fromHex: hex) ?? nsColor(fromHex: defaultCustomAccentHex)!)
        }
    }

    static var accentForeground: Color {
        foreground(for: currentAccentNSColor())
    }

    private static func currentAccentNSColor() -> NSColor {
        let defaults = UserDefaults.standard
        let mode = AppAccentMode(rawValue: defaults.string(forKey: "appearance.accentMode") ?? "") ?? .system
        switch mode {
        case .system: return .controlAccentColor
        case .neutral: return .systemGray
        case .custom:
            return nsColor(fromHex: defaults.string(forKey: "appearance.customAccentHex") ?? defaultCustomAccentHex)
                ?? nsColor(fromHex: defaultCustomAccentHex)!
        }
    }

    private static func foreground(for color: NSColor) -> Color {
        guard let c = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.62 ? .black : .white
    }

    static func nsColor(fromHex raw: String) -> NSColor? {
        let hex = raw.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    static func hex(from color: Color) -> String? {
        hex(from: NSColor(color))
    }

    static func hex(from color: NSColor) -> String? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((converted.redComponent * 255).rounded())
        let g = Int((converted.greenComponent * 255).rounded())
        let b = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
