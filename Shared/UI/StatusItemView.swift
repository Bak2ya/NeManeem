import AppKit

@MainActor
enum MenuBarSizing {
    static func configuredFont(_ settings: SettingsStore, twoLine: Bool) -> NSFont {
        let size = twoLine ? CGFloat(settings.menuFontSize) : CGFloat(max(settings.menuFontSize, 10.5))
        let base: NSFont
        if settings.menuFontFamily.isEmpty {
            base = NSFont.systemFont(ofSize: size, weight: .medium)
        } else {
            base = NSFont(name: settings.menuFontFamily, size: size) ?? NSFont.systemFont(ofSize: size, weight: .medium)
        }
        let feature: [[NSFontDescriptor.FeatureKey: Int]] = [[.typeIdentifier: 6, .selectorIdentifier: 0]]
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: feature])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

final class StatusItemView: NSView {
    var snapshot = NetworkSnapshot() { didSet { updateGeometry(); needsDisplay = true } }
    var dataLimitUsedBytes: UInt64 = 0 { didSet { updateGeometry(); needsDisplay = true } }
    var settings: SettingsStore? { didSet { updateGeometry(); needsDisplay = true } }
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var isPopoverShown = false { didSet { needsDisplay = true } }

    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: requiredWidth(), height: NSStatusBar.system.thickness)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let settings else { return }

        if hovering || isPopoverShown {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(isPopoverShown ? 0.36 : 0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 2), xRadius: 7, yRadius: 7).fill()
        }

        let top = settings.menuBarTopElements
        let bottom = settings.menuBarBottomElements
        if bottom.isEmpty {
            drawRow(top, in: bounds.insetBy(dx: 2, dy: 0), settings: settings, twoLine: false)
        } else {
            let gap = CGFloat(settings.rowSpacing)
            let rowHeight = max(1, (bounds.height - gap) / 2)
            drawRow(top, in: NSRect(x: 2, y: bounds.midY + gap / 2, width: bounds.width - 4, height: rowHeight), settings: settings, twoLine: true)
            drawRow(bottom, in: NSRect(x: 2, y: 0, width: bounds.width - 4, height: rowHeight), settings: settings, twoLine: true)
        }
    }

    private func drawRow(_ elements: [MenuBarElement], in rect: NSRect, settings: SettingsStore, twoLine: Bool) {
        guard !elements.isEmpty else { return }
        let font = MenuBarSizing.configuredFont(settings, twoLine: twoLine)
        let pieces = elements.map { attributedString(for: $0, settings: settings, font: font) }
        let widths = elements.map { elementWidth($0, settings: settings, font: font) }
        let gap = CGFloat(settings.metricGap)
        let totalWidth = widths.reduce(0, +) + gap * CGFloat(max(0, pieces.count - 1))
        // Two-line rows share one leading anchor. This keeps corresponding blocks
        // (for example upload/download values) on the same x position even when
        // one row contains an extra limit block. A single-line layout stays centered.
        var x = twoLine ? rect.minX : rect.midX - totalWidth / 2
        for (index, piece) in pieces.enumerated() {
            let slotRect = NSRect(x: x, y: rect.minY, width: widths[index], height: rect.height)
            switch elements[index] {
            case .uploadValue:
                drawSpeedValue(snapshot.uploadBytesPerSecond, in: slotRect, settings: settings, font: font)
            case .downloadValue:
                drawSpeedValue(snapshot.downloadBytesPerSecond, in: slotRect, settings: settings, font: font)
            default:
                let size = piece.size()
                let slotX = slotRect.minX + max(0, (slotRect.width - size.width) / 2)
                piece.draw(at: NSPoint(x: slotX, y: rect.midY - size.height / 2))
            }
            x += widths[index] + gap
        }
    }

    /// Draws live speed around one fixed invisible boundary inside the existing
    /// mode-specific value slot. Numeric glyphs grow leftward (right aligned) and
    /// the unit begins at the same x position (left aligned), so 8.0K / 102K or a
    /// K -> M transition cannot move the unit. The outer slot width is unchanged;
    /// selecting another unit mode still recalculates the normal menu-bar width.
    private func drawSpeedValue(_ bytesPerSecond: UInt64, in rect: NSRect, settings: SettingsStore, font: NSFont) {
        let components = SpeedFormatter.menuSpeedComponents(bytesPerSecond: bytesPerSecond, mode: settings.unitMode)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let numeric = NSAttributedString(string: components.numeric, attributes: attributes)
        let unit = NSAttributedString(string: components.unit, attributes: attributes)
        let numericSize = numeric.size()
        let unitSize = unit.size()

        let measurementAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let unitSlotWidth = SpeedFormatter.menuSpeedUnitSamples(for: settings.unitMode)
            .map { NSAttributedString(string: $0, attributes: measurementAttributes).size().width }
            .max() ?? 0
        let separatorWidth = components.separated
            ? NSAttributedString(string: " ", attributes: measurementAttributes).size().width
            : 0

        // Keep the current elementWidth() reservation exactly as-is. The widest
        // selected-family unit owns the right slot; all remaining width is the
        // numeric slot. No extra menu-bar points are introduced by this alignment.
        let unitStartX = rect.maxX - unitSlotWidth
        let numericBoundaryX = unitStartX - separatorWidth
        numeric.draw(at: NSPoint(x: numericBoundaryX - numericSize.width,
                                 y: rect.midY - numericSize.height / 2))
        unit.draw(at: NSPoint(x: unitStartX,
                              y: rect.midY - unitSize.height / 2))
    }

    private func attributedString(for element: MenuBarElement, settings: SettingsStore, font: NSFont) -> NSAttributedString {
        let string: String
        switch element {
        case .uploadArrow: string = "↑"
        case .uploadValue: string = SpeedFormatter.string(bytesPerSecond: snapshot.uploadBytesPerSecond, mode: settings.unitMode)
        case .downloadArrow: string = "↓"
        case .downloadValue: string = SpeedFormatter.string(bytesPerSecond: snapshot.downloadBytesPerSecond, mode: settings.unitMode)
        case .limitValue: string = limitValueString(settings)
        case .limitPercent: string = limitPercentString(settings)
        case .limitLight: string = limitLightString(settings)
        }
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }

    private func displayedLimitBytes(_ settings: SettingsStore) -> UInt64 {
        let limit = settings.dataLimitBytes
        guard limit > 0 else { return 0 }
        switch settings.dataLimitDisplayMode {
        case .used: return min(dataLimitUsedBytes, limit)
        case .remaining: return dataLimitUsedBytes >= limit ? 0 : limit - dataLimitUsedBytes
        }
    }

    private func limitValueString(_ settings: SettingsStore) -> String {
        guard settings.dataLimitEnabled, settings.dataLimitBytes > 0 else { return "—" }
        return SpeedFormatter.quantity(bytes: displayedLimitBytes(settings), mode: settings.unitMode)
    }

    private func limitPercentString(_ settings: SettingsStore) -> String {
        let limit = settings.dataLimitBytes
        guard settings.dataLimitEnabled, limit > 0 else { return "—" }
        let usedPercent = min(100, (Double(dataLimitUsedBytes) / Double(limit)) * 100)
        let value = settings.dataLimitDisplayMode == .used ? usedPercent : max(0, 100 - min(100, usedPercent))
        return String(format: "%.0f%%", value)
    }

    private func limitLightString(_ settings: SettingsStore) -> String {
        let limit = settings.dataLimitBytes
        guard settings.dataLimitEnabled, limit > 0 else { return "⚪️" }
        guard settings.dataLimitWarningLightLinked, settings.dataLimitWarningEnabled, !settings.dataLimitWarningRules.isEmpty else { return "🟢" }

        let rules = settings.dataLimitWarningRules
        func thresholdUsedBytes(_ rule: DataLimitWarningRule) -> UInt64 {
            switch rule.mode {
            case .percentage:
                return UInt64(Double(limit) * min(99, max(1, rule.percentage)) / 100.0)
            case .remainingAmount:
                return limit > rule.remainingBytes ? limit - rule.remainingBytes : 0
            }
        }
        func configuredThreshold(for identifier: String, allowsLimit: Bool) -> UInt64? {
            guard identifier != "__off__" else { return nil }
            if allowsLimit, identifier == "__limit__" { return limit }
            guard let rule = rules.first(where: { $0.id.uuidString == identifier }) else { return nil }
            return thresholdUsedBytes(rule)
        }

        let redThreshold = configuredThreshold(for: settings.dataLimitWarningLightRedRuleID, allowsLimit: true)
        let orangeThreshold = configuredThreshold(for: settings.dataLimitWarningLightOrangeRuleID, allowsLimit: true)
        let yellowThreshold = configuredThreshold(for: settings.dataLimitWarningLightYellowRuleID, allowsLimit: false)
        if let redThreshold, dataLimitUsedBytes >= redThreshold { return "🔴" }
        if let orangeThreshold, dataLimitUsedBytes >= orangeThreshold { return "🟠" }
        if let yellowThreshold, dataLimitUsedBytes >= yellowThreshold { return "🟡" }
        return "🟢"
    }

    private func elementWidth(_ element: MenuBarElement, settings: SettingsStore, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let samples: [String]
        switch element {
        case .uploadArrow: samples = ["↑"]
        case .downloadArrow: samples = ["↓"]
        case .uploadValue, .downloadValue:
            samples = SpeedFormatter.menuWidthSamples(for: settings.unitMode)
        case .limitValue:
            samples = SpeedFormatter.menuQuantityWidthSamples(for: settings.unitMode)
        case .limitPercent:
            // Reserve only the normal 0...99% width. At the one-off 100% boundary,
            // include the live value so the status item widens temporarily instead of
            // permanently spending an extra digit of menu-bar space.
            samples = ["0%", "99%", limitPercentString(settings)]
        case .limitLight:
            samples = ["🟢", "🟡", "🔴", "⚪️"]
        }
        return ceil(samples.map { NSAttributedString(string: $0, attributes: attributes).size().width }.max() ?? 0)
    }

    private func rowWidth(_ elements: [MenuBarElement], settings: SettingsStore, twoLine: Bool) -> CGFloat {
        guard !elements.isEmpty else { return 0 }
        let font = MenuBarSizing.configuredFont(settings, twoLine: twoLine)
        let widths = elements.map { elementWidth($0, settings: settings, font: font) }
        return widths.reduce(0, +) + CGFloat(settings.metricGap) * CGFloat(max(0, widths.count - 1))
    }

    private func requiredWidth() -> CGFloat {
        guard let settings else { return 40 }
        let twoLine = !settings.menuBarBottomElements.isEmpty
        let top = rowWidth(settings.menuBarTopElements, settings: settings, twoLine: twoLine)
        let bottom = rowWidth(settings.menuBarBottomElements, settings: settings, twoLine: twoLine)
        return ceil(max(24, max(top, bottom) + 6))
    }

    func updateGeometry() {
        invalidateIntrinsicContentSize()
        frame.size.width = requiredWidth()
    }
}
