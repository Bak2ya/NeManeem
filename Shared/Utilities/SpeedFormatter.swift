import Foundation

enum SpeedFormatter {
    private static let figureSpace = "\u{2007}"

    static func string(bytesPerSecond: UInt64, mode: SpeedUnitMode) -> String {
        switch mode {
        case .compactBytes: return compactThreeSlot(Double(bytesPerSecond), units: ["B", "K", "M", "G", "T"], separated: false)
        case .bytesPerSecond: return compactThreeSlot(Double(bytesPerSecond), units: ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"], separated: true)
        case .bitsPerSecond: return compactThreeSlot(Double(bytesPerSecond &* 8), units: ["bps", "Kbps", "Mbps", "Gbps", "Tbps"], separated: true)
        }
    }

    /// Cumulative quantity using the same unit family chosen for the live speed
    /// display, but without a per-second suffix. Used by the compact session row.
    static func quantity(bytes: UInt64, mode: SpeedUnitMode) -> String {
        switch mode {
        case .compactBytes:
            return compactThreeSlot(Double(bytes), units: ["B", "K", "M", "G", "T"], separated: false)
        case .bytesPerSecond:
            return compactThreeSlot(Double(bytes), units: ["B", "KB", "MB", "GB", "TB"], separated: true)
        case .bitsPerSecond:
            return compactThreeSlot(Double(bytes &* 8), units: ["b", "Kb", "Mb", "Gb", "Tb"], separated: true)
        }
    }

    /// Human-readable byte count for settings/statistics where compact table width
    /// is not the primary constraint.
    static func bytes(_ value: UInt64) -> String {
        if value == 0 { return "0 KB" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1000, index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        if index > 0 && amount < 10 { return String(format: "%.1f %@", amount, units[index]) }
        return "\(Int(amount.rounded())) \(units[index])"
    }

    /// Compact byte count for Popover/Monitor table cells. The numeric portion is
    /// always at most three character slots and uses figure spaces for right alignment:
    /// `9.7K`, ` 87K`, `999K`, `0.9M`.
    static func statusBytes(_ value: UInt64) -> String {
        compactThreeSlot(Double(value), units: ["B", "K", "M", "G", "T"], separated: false)
    }

    static func maximumStatusSample(for mode: SpeedUnitMode) -> String {
        switch mode {
        case .compactBytes: return "999M"
        case .bytesPerSecond: return "999 MB/s"
        case .bitsPerSecond: return "999 Mbps"
        }
    }

    static func maximumStatusByteSample() -> String { "999G" }

    static func menuWidthSamples(for mode: SpeedUnitMode) -> [String] {
        switch mode {
        case .compactBytes:
            return ["999B", "999K", "999M", "999G", "9.9M", "9.9G"]
        case .bytesPerSecond:
            return ["999 B/s", "999 KB/s", "999 MB/s", "999 GB/s", "9.9 MB/s", "9.9 GB/s"]
        case .bitsPerSecond:
            return ["999 bps", "999 Kbps", "999 Mbps", "999 Gbps", "9.9 Mbps", "9.9 Gbps"]
        }
    }

    /// Separates the live menu-bar speed into numeric and unit components without
    /// changing the existing compact formatting thresholds. StatusItemView uses
    /// this to keep one invisible boundary fixed: the numeric side right-aligns
    /// into it and the unit side left-aligns out of it.
    static func menuSpeedComponents(bytesPerSecond: UInt64, mode: SpeedUnitMode) -> (numeric: String, unit: String, separated: Bool) {
        let formatted = string(bytesPerSecond: bytesPerSecond, mode: mode)
        switch mode {
        case .compactBytes:
            guard let unit = formatted.last else { return (formatted, "", false) }
            let numeric = String(formatted.dropLast()).replacingOccurrences(of: figureSpace, with: "")
            return (numeric, String(unit), false)
        case .bytesPerSecond, .bitsPerSecond:
            guard let separator = formatted.lastIndex(of: " ") else { return (formatted, "", false) }
            let numeric = String(formatted[..<separator]).replacingOccurrences(of: figureSpace, with: "")
            let unit = String(formatted[formatted.index(after: separator)...])
            return (numeric, unit, true)
        }
    }

    /// Unit samples for the currently selected menu-bar unit family. The status
    /// item keeps a fixed unit-start anchor only within this selected family; when
    /// the user changes the unit setting, the normal mode-specific status width is
    /// recalculated instead of globally reserving the widest family.
    static func menuSpeedUnitSamples(for mode: SpeedUnitMode) -> [String] {
        switch mode {
        case .compactBytes:
            return ["B", "K", "M", "G", "T"]
        case .bytesPerSecond:
            return ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        case .bitsPerSecond:
            return ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
        }
    }

    /// Width samples for cumulative quantities shown in the menu bar. The unit family
    /// follows the live-speed unit choice but intentionally omits the per-second suffix.
    static func menuQuantityWidthSamples(for mode: SpeedUnitMode) -> [String] {
        switch mode {
        case .compactBytes:
            return ["999B", "999K", "999M", "999G", "9.9M", "9.9G"]
        case .bytesPerSecond:
            return ["999 B", "999 KB", "999 MB", "999 GB", "9.9 MB", "9.9 GB"]
        case .bitsPerSecond:
            return ["999 b", "999 Kb", "999 Mb", "999 Gb", "9.9 Mb", "9.9 Gb"]
        }
    }

    /// Uses binary step size (1024) but promotes once the current display would need
    /// four integer digits. Therefore 999K stays 999K while 1000K...1023K becomes
    /// 0.9M instead of widening the table. Values are truncated, never rounded up.
    private static func compactThreeSlot(_ rawValue: Double, units: [String], separated: Bool) -> String {
        var amount = max(0, rawValue)
        var index = 0
        while amount >= 1000, index < units.count - 1 {
            amount /= 1024.0
            index += 1
        }

        let numeric: String
        if index > 0 && amount < 10 {
            let truncated = floor(amount * 10.0) / 10.0
            numeric = String(format: "%.1f", truncated)
        } else {
            let integer = Int(floor(amount))
            let text = String(min(integer, 999))
            numeric = String(repeating: figureSpace, count: max(0, 3 - text.count)) + text
        }
        return separated ? "\(numeric) \(units[index])" : "\(numeric)\(units[index])"
    }
}
