import AppKit
import SwiftUI

// Reusable settings editors live here so MainWindow.swift follows the same
// order as the visible sidebar instead of ending with control implementation.

let settingsInlineChoiceWidth: CGFloat = 420
/// Compact selection buttons follow the thin pre-Build-109 visual reference.
/// Two points of container padding on each side make the complete control 28pt.
let settingsCompactSegmentContentHeight: CGFloat = 24
/// Build 110's approved content-fit formula reserves 24pt around the label:
/// 12pt on each horizontal side. Keep this explicit so custom-input slots use
/// the same established selection grammar rather than a newly guessed padding.
let settingsCompactSegmentHorizontalPadding: CGFloat = 12
let settingsCustomInputHorizontalPadding: CGFloat = 6
let settingsCustomInputSpacing: CGFloat = 3
let settingsCustomInputConfirmationWidth: CGFloat = 12
let settingsCustomInputConfirmationTrailingPadding: CGFloat = 5
let settingsCustomInputMinimumFieldWidth: CGFloat = 28
let settingsCustomInputMaximumFieldWidth: CGFloat = 44

func compactSegmentNaturalWidth(_ label: String) -> CGFloat {
    max(52, min(164, settingsCompactSegmentHorizontalPadding * 2 + compactTextWidth(label)))
}

private func compactTextWidth(_ text: String) -> CGFloat {
    let font = NSFont.preferredFont(forTextStyle: .body)
    return ceil((text as NSString).size(withAttributes: [.font: font]).width)
}

/// A custom segment never grows when it turns into an input field. Its width
/// reserves the largest of the unselected label and the complete editing
/// contents (numeric sample, existing field padding, confirmation, and unit).
/// This is deliberately state-independent.
func fixedCustomInputSlotWidth(label: String,
                               inputSample: String,
                               trailingText: String? = nil,
                               confirmationTrailingPadding: CGFloat = settingsCustomInputConfirmationTrailingPadding) -> CGFloat {
    // The field itself scrolls horizontally while editing, so a long sample must
    // not inflate the whole segment. Reserve enough room for a short numeric edit,
    // the unit and the confirmation control; the external slot then stays compact
    // and state-independent.
    let sampledFieldWidth = min(settingsCustomInputMaximumFieldWidth,
                                max(settingsCustomInputMinimumFieldWidth, compactTextWidth(inputSample)))
    let inputStateWidth = settingsCustomInputHorizontalPadding
        + sampledFieldWidth
        + settingsCustomInputSpacing * CGFloat(trailingText == nil ? 1 : 2)
        + (trailingText.map(compactTextWidth) ?? 0)
        + settingsCustomInputConfirmationWidth
        + confirmationTrailingPadding
    return max(compactSegmentNaturalWidth(label), inputStateWidth)
}

func customInputTextFieldWidth(slotWidth: CGFloat,
                               trailingText: String? = nil,
                               confirmationTrailingPadding: CGFloat = settingsCustomInputConfirmationTrailingPadding) -> CGFloat {
    let fixedWidth = settingsCustomInputHorizontalPadding
        + settingsCustomInputSpacing * CGFloat(trailingText == nil ? 1 : 2)
        + (trailingText.map(compactTextWidth) ?? 0)
        + settingsCustomInputConfirmationWidth
        + confirmationTrailingPadding
    return max(settingsCustomInputMinimumFieldWidth,
               min(settingsCustomInputMaximumFieldWidth, slotWidth - fixedWidth))
}


/// Native inline editor for the two same-slot controls that remained visually
/// broken on the user's signed Mac (hide/closed-data delay and Data Limit
/// re-alert).  A borderless NSTextField, unit label, and clickable check label
/// share the same AppKit text geometry, avoiding SwiftUI TextField baseline
/// differences inside a 24pt segmented slot.
struct NMInlineCustomNumericEditor: NSViewRepresentable {
    @Binding var text: String
    let unit: String
    let fieldWidth: CGFloat
    let confirmationAccessibilityLabel: String
    var confirmationWidth: CGFloat = settingsCustomInputConfirmationWidth
    var spacing: CGFloat = settingsCustomInputSpacing
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onEdit: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NMInlineCustomNumericEditor

        init(_ parent: NMInlineCustomNumericEditor) {
            self.parent = parent
        }

        @objc func commit() {
            parent.onCommit()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onEdit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }

    final class InlineView: NSView {
        let field = NSTextField()
        let unitLabel = NSTextField(labelWithString: "")
        let confirmLabel = ClickableLabel(text: "✓")
        var fieldWidth: CGFloat = 32
        var confirmationWidth: CGFloat = 12
        var spacing: CGFloat = 3

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            field.font = font
            unitLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            confirmLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

            unitLabel.sizeToFit()
            confirmLabel.sizeToFit()

            // All three controls use the same single-line text height and y origin.
            // This makes their glyph baselines visually identical on real AppKit,
            // unlike the mixed SwiftUI TextField/Text/Button implementation.
            let textHeight = max(18, ceil(font.ascender - font.descender + font.leading))
            let y = floor((bounds.height - textHeight) / 2)
            var x: CGFloat = 0
            field.frame = NSRect(x: x, y: y, width: fieldWidth, height: textHeight)
            x += fieldWidth + spacing
            unitLabel.frame = NSRect(x: x, y: y, width: ceil(unitLabel.fittingSize.width), height: textHeight)
            x += ceil(unitLabel.fittingSize.width) + spacing
            confirmLabel.frame = NSRect(x: x, y: y, width: confirmationWidth, height: textHeight)
        }
    }

    final class ClickableLabel: NSTextField {
        var onClick: (() -> Void)?

        convenience init(text: String) {
            self.init(frame: .zero)
            stringValue = text
            isEditable = false
            isSelectable = false
            isBordered = false
            drawsBackground = false
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> InlineView {
        let view = InlineView()
        view.field.isBordered = false
        view.field.drawsBackground = false
        view.field.focusRingType = .none
        view.field.alignment = .right
        view.field.usesSingleLineMode = true
        view.field.cell?.usesSingleLineMode = true
        view.field.delegate = context.coordinator
        view.field.target = context.coordinator
        view.field.action = #selector(Coordinator.commit)

        view.unitLabel.textColor = .secondaryLabelColor
        view.unitLabel.alignment = .left
        view.unitLabel.lineBreakMode = .byClipping

        view.confirmLabel.textColor = .controlAccentColor
        view.confirmLabel.alignment = .center
        view.confirmLabel.onClick = { context.coordinator.commit() }
        view.confirmLabel.setAccessibilityLabel(confirmationAccessibilityLabel)

        view.addSubview(view.field)
        view.addSubview(view.unitLabel)
        view.addSubview(view.confirmLabel)

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.makeFirstResponder(view.field)
            view.field.selectText(nil)
        }
        return view
    }

    func updateNSView(_ view: InlineView, context: Context) {
        context.coordinator.parent = self
        if view.field.stringValue != text { view.field.stringValue = text }
        view.unitLabel.stringValue = unit
        view.fieldWidth = fieldWidth
        view.confirmationWidth = confirmationWidth
        view.spacing = spacing
        view.confirmLabel.onClick = { context.coordinator.commit() }
        view.confirmLabel.setAccessibilityLabel(confirmationAccessibilityLabel)
        view.needsLayout = true
    }
}

func nmSelectAllCurrentTextEditor() {
    DispatchQueue.main.async {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            editor.selectAll(nil)
        } else if let field = NSApp.keyWindow?.firstResponder as? NSTextField,
                  let editor = field.currentEditor() {
            editor.selectAll(nil)
        }
    }
}

extension View {
    /// Numeric fields use replace-first editing: clicking an existing value selects
    /// the whole value so the next keystroke replaces it. Programmatic focus can
    /// call `nmSelectAllCurrentTextEditor()` after setting FocusState as well.
    func nmSelectAllOnEdit() -> some View {
        simultaneousGesture(TapGesture().onEnded { nmSelectAllCurrentTextEditor() })
    }
}

func equalSegmentControlWidth(_ labels: [String], segmentCount: Int? = nil) -> CGFloat {
    let count = max(1, segmentCount ?? labels.count)
    let segmentWidth = labels.map(compactSegmentNaturalWidth).max() ?? 52
    return 4 + CGFloat(max(0, count - 1)) + segmentWidth * CGFloat(count)
}

private func compactChoiceWidth(_ labels: [String]) -> CGFloat {
    4 + CGFloat(max(0, labels.count - 1)) + labels.map(compactSegmentNaturalWidth).reduce(0, +)
}

func naturalSegmentControlWidth(_ labels: [String], fixedSlotWidths: [Int: CGFloat] = [:]) -> CGFloat {
    let widths = labels.indices.map { index -> CGFloat in
        fixedSlotWidths[index] ?? compactSegmentNaturalWidth(labels[index])
    }
    return 4 + CGFloat(max(0, labels.count - 1)) + widths.reduce(0, +)
}

/// Returns content-aware segment widths without wasting equal space on short
/// labels such as `3s`. The visual grammar stays identical; only the amount of
/// space each localized label needs is different.
func compactSegmentWidths(_ labels: [String],
                          totalWidth: CGFloat = settingsInlineChoiceWidth,
                          fixedSlotWidths: [Int: CGFloat] = [:]) -> [CGFloat] {
    guard !labels.isEmpty else { return [] }
    let separatorSpace = CGFloat(max(0, labels.count - 1))
    let innerWidth = max(1, totalWidth - 4 - separatorSpace)
    let ideals = labels.map { label -> CGFloat in
        // `count` is intentionally only an approximation. It keeps the layout
        // deterministic and cheap while giving longer localized labels more room.
        max(58, min(148, 28 + CGFloat(label.count) * 7))
    }
    let fixedIndices = Set(fixedSlotWidths.keys.filter { labels.indices.contains($0) })
    let fixedTotal = fixedIndices.reduce(CGFloat.zero) { $0 + max(0, fixedSlotWidths[$1] ?? 0) }
    let flexibleIndices = labels.indices.filter { !fixedIndices.contains($0) }
    let flexibleIdealTotal = flexibleIndices.reduce(CGFloat.zero) { $0 + ideals[$1] }
    let flexibleWidth = max(1, innerWidth - fixedTotal)
    return labels.indices.map { index in
        if let fixed = fixedSlotWidths[index] { return fixed }
        guard flexibleIdealTotal > 0 else { return flexibleWidth / CGFloat(max(1, flexibleIndices.count)) }
        return flexibleWidth * (ideals[index] / flexibleIdealTotal)
    }
}

struct CompactSegmentedChoice<SelectionValue: Hashable>: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, title: String)]
    let onSelect: ((SelectionValue) -> Void)?
    let controlWidth: CGFloat?
    let equalSegmentWidths: Bool

    init(_ title: String,
         selection: Binding<SelectionValue>,
         options: [(SelectionValue, String)],
         onSelect: ((SelectionValue) -> Void)? = nil,
         controlWidth: CGFloat? = nil,
         equalSegmentWidths: Bool = false) {
        self.title = title
        self._selection = selection
        self.options = options.map { (value: $0.0, title: $0.1) }
        self.onSelect = onSelect
        self.controlWidth = controlWidth
        self.equalSegmentWidths = equalSegmentWidths
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(title)
                Spacer(minLength: 10)
                control
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    control
                }
            }
        }
    }

    private var control: some View {
        let labels = options.map(\.title)
        let totalWidth = controlWidth
            ?? (equalSegmentWidths
                ? equalSegmentControlWidth(labels)
                : (options.count <= 2 ? compactChoiceWidth(labels) : settingsInlineChoiceWidth))
        let widths = equalSegmentWidths
            ? Array(repeating: max(1, (totalWidth - 4 - CGFloat(max(0, labels.count - 1))) / CGFloat(max(1, labels.count))), count: labels.count)
            : compactSegmentWidths(labels, totalWidth: totalWidth)
        return HStack(spacing: 1) {
            ForEach(options.indices, id: \.self) { index in
                segmentButton(at: index, width: widths[index])
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.6)
        }
        .frame(width: totalWidth)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segmentButton(at index: Int, width: CGFloat) -> some View {
        let option = options[index]
        let isSelected = selection == option.value
        let textWeight: Font.Weight = isSelected ? .semibold : .regular
        let isInactive = controlActiveState == .inactive || !isEnabled
        let textColor: Color
        if isSelected {
            textColor = isInactive ? Color(nsColor: .unemphasizedSelectedTextColor) : NeManeemTheme.accentForeground
        } else {
            textColor = isEnabled ? .primary : Color(nsColor: .disabledControlTextColor)
        }
        let fillColor: Color = isSelected
            ? (isInactive ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : NeManeemTheme.accent)
            : .clear

        return Button {
            selection = option.value
            onSelect?(option.value)
        } label: {
            Text(option.title)
                .font(.body.weight(textWeight))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: width)
                .frame(height: settingsCompactSegmentContentHeight)
                .background(fillColor, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RetentionPeriodEditor: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    @Binding var days: Int
    let t: (String) -> String
    @State private var customText = ""
    @State private var editingCustom = false
    @FocusState private var customFocused: Bool

    private let presets = [7, 30, 365]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(title)
                Spacer(minLength: 10)
                control
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    control
                }
            }
        }
    }

    private var control: some View {
        let labels = [presetTitle(7), presetTitle(30), presetTitle(365), t("unlimited"), customLabel]
        let customSlotWidth = fixedCustomInputSlotWidth(label: t("custom"),
                                                        inputSample: "9999",
                                                        trailingText: t("days"),
                                                        confirmationTrailingPadding: 4)
        let widths = labels.indices.map { index in
            index == 4 ? customSlotWidth : compactSegmentNaturalWidth(labels[index])
        }
        let totalWidth = naturalSegmentControlWidth(labels, fixedSlotWidths: [4: customSlotWidth])
        return HStack(spacing: 1) {
            ForEach(presets.indices, id: \.self) { index in
                let value = presets[index]
                choice(labels[index], selected: !editingCustom && days == value) {
                    editingCustom = false
                    customFocused = false
                    days = value
                }
                .frame(width: widths[index])
            }
            choice(labels[3], selected: !editingCustom && days == 0) {
                editingCustom = false
                customFocused = false
                days = 0
            }
            .frame(width: widths[3])

            Group {
                if editingCustom {
                    let unit = t("days")
                    let fieldWidth = customInputTextFieldWidth(slotWidth: customSlotWidth,
                                                               trailingText: unit,
                                                               confirmationTrailingPadding: 4)
                    HStack(alignment: .firstTextBaseline, spacing: settingsCustomInputSpacing) {
                        TextField("", text: $customText)
                            .textFieldStyle(.plain)
                            .font(.body.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: fieldWidth)
                            .focused($customFocused)
                            .onSubmit(commit)
                            .nmSelectAllOnEdit()
                        Text(unit)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button(action: commit) {
                            Text("✓")
                                .font(.body.weight(.semibold))
                                .frame(width: settingsCustomInputConfirmationWidth)
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 4)
                    }
                    .padding(.leading, settingsCustomInputHorizontalPadding)
                    .frame(width: customSlotWidth, height: settingsCompactSegmentContentHeight, alignment: .center)
                    .background(NeManeemTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(NeManeemTheme.accent.opacity(0.55), lineWidth: 0.8) }
                    .onExitCommand {
                        editingCustom = false
                        customFocused = false
                    }
                } else {
                    choice(customLabel, selected: isCustom) {
                        customText = isCustom ? "\(days)" : ""
                        editingCustom = true
                        DispatchQueue.main.async {
                            customFocused = true
                            nmSelectAllCurrentTextEditor()
                        }
                    }
                }
            }
            .frame(width: widths[4])
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.6) }
        .frame(width: totalWidth)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var isCustom: Bool { days > 0 && !presets.contains(days) }
    private var customLabel: String { isCustom ? "\(days)\(t("days"))" : t("custom") }
    private func presetTitle(_ value: Int) -> String { String(format: t("retentionDaysFormat"), value) }

    private func choice(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected
                    ? ((controlActiveState == .inactive || !isEnabled) ? Color(nsColor: .unemphasizedSelectedTextColor) : NeManeemTheme.accentForeground)
                    : (isEnabled ? Color.primary : Color(nsColor: .disabledControlTextColor)))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: settingsCompactSegmentContentHeight)
                .background(selected
                    ? ((controlActiveState == .inactive || !isEnabled) ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : NeManeemTheme.accent)
                    : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        guard let value = Int(customText.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return }
        days = value
        editingCustom = false
        customFocused = false
        customText = ""
    }
}

struct ClosedDataRetentionEditor: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    @Binding var value: Double
    let t: (String) -> String
    var zeroLabel: String? = nil
    var normalizer: (Double) -> Double = SettingsStore.normalizeClosedDataRetention
    @State private var customText = ""
    @State private var lastCustomValue: Double?
    @State private var editingCustom = false
    @State private var invalidCustom = false
    @FocusState private var customFieldFocused: Bool

    private let presets: [Double] = [0, 3, 5, 10]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                Text(title)
                Spacer(minLength: 10)
                retentionControls
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    retentionControls
                }
            }
        }
        .onAppear { if isCustomValue { lastCustomValue = value } }
        .onChange(of: value) { newValue in
            if isCustomValue { lastCustomValue = newValue }
            if editingCustom, !customFieldFocused { customText = formatted(newValue) }
        }
    }

    private var retentionControls: some View {
        let labels = [zeroLabel ?? t("stopImmediately"), "3s", "5s", "10s", customDisplayLabel]
        let customSlotWidth = fixedCustomInputSlotWidth(label: t("custom"), inputSample: "999.9", trailingText: "s")
        let widths = labels.indices.map { index in
            index == 4 ? customSlotWidth : compactSegmentNaturalWidth(labels[index])
        }
        let totalWidth = naturalSegmentControlWidth(labels, fixedSlotWidths: [4: customSlotWidth])
        return HStack(spacing: 1) {
            choiceButton(labels[0], selected: isSelected(0)) { choosePreset(0) }
                .frame(width: widths[0])
            choiceButton(labels[1], selected: isSelected(3)) { choosePreset(3) }
                .frame(width: widths[1])
            choiceButton(labels[2], selected: isSelected(5)) { choosePreset(5) }
                .frame(width: widths[2])
            choiceButton(labels[3], selected: isSelected(10)) { choosePreset(10) }
                .frame(width: widths[3])
            customSlot.frame(width: widths[4])
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.6) }
        .frame(width: totalWidth)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var customSlot: some View {
        let slotWidth = fixedCustomInputSlotWidth(label: t("custom"), inputSample: "999.9", trailingText: "s")
        if editingCustom {
            let fieldWidth = customInputTextFieldWidth(slotWidth: slotWidth, trailingText: "s")
            NMInlineCustomNumericEditor(
                text: $customText,
                unit: "s",
                fieldWidth: fieldWidth,
                confirmationAccessibilityLabel: t("apply"),
                onCommit: commit,
                onCancel: cancelCustomEdit,
                onEdit: { invalidCustom = false }
            )
            .frame(height: settingsCompactSegmentContentHeight)
            .padding(.leading, settingsCustomInputHorizontalPadding)
            .padding(.trailing, settingsCustomInputConfirmationTrailingPadding)
            .frame(width: slotWidth, height: settingsCompactSegmentContentHeight, alignment: .center)
            .background(invalidCustom ? Color.red.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(invalidCustom ? Color.red.opacity(0.9) : NeManeemTheme.accent.opacity(0.55), lineWidth: invalidCustom ? 1.2 : 0.8)
            }
            .onExitCommand(perform: cancelCustomEdit)
        } else {
            choiceButton(customDisplayLabel, selected: isCustomValue) { beginCustomEdit() }
        }
    }

    private var customDisplayLabel: String { isCustomValue ? "\(formatted(value))s" : t("custom") }
    private var isCustomValue: Bool { !presets.contains { abs($0 - value) < 0.001 } }
    private func isSelected(_ preset: Double) -> Bool { !editingCustom && abs(value - preset) < 0.001 }

    private func choiceButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected
                    ? ((controlActiveState == .inactive || !isEnabled) ? Color(nsColor: .unemphasizedSelectedTextColor) : NeManeemTheme.accentForeground)
                    : (isEnabled ? Color.primary : Color(nsColor: .disabledControlTextColor)))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: settingsCompactSegmentContentHeight)
                .background(selected
                    ? ((controlActiveState == .inactive || !isEnabled) ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : NeManeemTheme.accent)
                    : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choosePreset(_ preset: Double) {
        if isCustomValue { lastCustomValue = value }
        editingCustom = false
        invalidCustom = false
        customFieldFocused = false
        customText = ""
        value = normalizer(preset)
    }

    private func beginCustomEdit() {
        let initial = isCustomValue ? value : (lastCustomValue ?? value)
        customText = formatted(initial)
        invalidCustom = false
        editingCustom = true
        DispatchQueue.main.async {
            customFieldFocused = true
            nmSelectAllCurrentTextEditor()
        }
    }

    private func cancelCustomEdit() {
        customText = ""
        invalidCustom = false
        editingCustom = false
        customFieldFocused = false
    }

    private func commit() {
        guard let parsed = SettingsStore.parseClosedDataRetentionText(customText) else {
            invalidCustom = true
            customFieldFocused = true
            return
        }
        let normalized = normalizer(parsed)
        value = normalized
        lastCustomValue = normalized
        customText = ""
        invalidCustom = false
        editingCustom = false
        customFieldFocused = false
    }

    private func formatted(_ seconds: Double) -> String {
        if abs(seconds.rounded() - seconds) < 0.001 { return String(Int(seconds.rounded())) }
        return String(format: "%.1f", seconds)
    }
}


struct RefreshIntervalEditor: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled
    let title: String?
    @Binding var value: Double
    /// When supplied, this editor adds an explicit inherited-value segment.
    /// The stored numeric value is retained so turning inheritance off restores
    /// the user's last individual selection.
    var followsMenuBar: Binding<Bool>?
    let t: (String) -> String
    @State private var customText = ""
    @State private var lastCustomValue: Double?
    @State private var editingCustom = false
    @State private var invalidCustom = false
    @FocusState private var customFieldFocused: Bool

    // Final user-facing presets. The 3 s preset is the everyday default.
    private let presets: [Double] = [0.25, 3.0, 10.0]

    init(title: String?, value: Binding<Double>, followsMenuBar: Binding<Bool>? = nil, t: @escaping (String) -> String) {
        self.title = title
        self._value = value
        self.followsMenuBar = followsMenuBar
        self.t = t
    }

    var body: some View {
        Group {
            if let title, !title.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        Text(title)
                        Spacer(minLength: 10)
                        intervalControls
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            intervalControls
                        }
                    }
                }
            } else {
                intervalControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear {
            if isCustomValue { lastCustomValue = value }
        }
        .onChange(of: value) { newValue in
            if !presets.contains(where: { abs($0 - newValue) < 0.001 }) {
                lastCustomValue = newValue
            }
            if editingCustom, !customFieldFocused {
                customText = formatted(newValue)
            }
        }
    }

    private var intervalControls: some View {
        let presetLabels = ["0.25s (\(t("realtime")))", "3s", "10s", customDisplayLabel]
        let inheritedLabel = t("sameAsMenuBar")
        // The four common choices use the exact same content-fit widths on Menu
        // Bar, Popover, and Monitor. Only the inherited option has its own width.
        let stablePresetLabels = [presetLabels[0], presetLabels[1], presetLabels[2], t("custom")]
        let customSlotWidth = fixedCustomInputSlotWidth(label: t("custom"), inputSample: "999.9", trailingText: "s")
        let presetWidths = stablePresetLabels.enumerated().map { index, label in
            index == stablePresetLabels.count - 1 ? customSlotWidth : compactSegmentNaturalWidth(label)
        }
        let inheritedWidth = compactSegmentNaturalWidth(inheritedLabel)
        let totalWidth = 4
            + presetWidths.reduce(0, +)
            + CGFloat(presetWidths.count - 1)
            + (followsMenuBar == nil ? 0 : inheritedWidth + 1)
        return HStack(spacing: 1) {
            if let followsMenuBar {
                intervalButton(inheritedLabel, selected: followsMenuBar.wrappedValue) {
                    followsMenuBar.wrappedValue = true
                    cancelCustomEdit()
                }
                .frame(width: inheritedWidth)
            }
            intervalButton(presetLabels[0], selected: isSelected(0.25)) { choosePreset(0.25) }
                .frame(width: presetWidths[0])
            intervalButton(presetLabels[1], selected: isSelected(3.0)) { choosePreset(3.0) }
                .frame(width: presetWidths[1])
            intervalButton(presetLabels[2], selected: isSelected(10.0)) { choosePreset(10.0) }
                .frame(width: presetWidths[2])
            customSlot.frame(width: presetWidths[3])
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.6) }
        .frame(width: totalWidth)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var customSlot: some View {
        let slotWidth = fixedCustomInputSlotWidth(label: t("custom"), inputSample: "999.9", trailingText: "s")
        if editingCustom {
            let fieldWidth = customInputTextFieldWidth(slotWidth: slotWidth, trailingText: "s")
            HStack(alignment: .firstTextBaseline, spacing: settingsCustomInputSpacing) {
                TextField("", text: $customText)
                    .textFieldStyle(.plain)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: fieldWidth)
                    .focused($customFieldFocused)
                    .onSubmit(commit)
                    .onChange(of: customText) { _ in invalidCustom = false }
                    .nmSelectAllOnEdit()
                Text("s")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button(action: commit) {
                    Text("✓")
                        .font(.body.weight(.semibold))
                        .frame(width: settingsCustomInputConfirmationWidth)
                }
                .buttonStyle(.borderless)
                .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(t("apply"))
                .padding(.trailing, settingsCustomInputConfirmationTrailingPadding)
            }
            .padding(.leading, settingsCustomInputHorizontalPadding)
            .frame(width: slotWidth, height: settingsCompactSegmentContentHeight, alignment: .center)
            .background(invalidCustom ? Color.red.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(invalidCustom ? Color.red.opacity(0.9) : NeManeemTheme.accent.opacity(0.55), lineWidth: invalidCustom ? 1.2 : 0.8)
            }
            .help(t("minimumIntervalHelp"))
            .onExitCommand(perform: cancelCustomEdit)
        } else {
            intervalButton(customDisplayLabel, selected: isCustomValue) {
                followsMenuBar?.wrappedValue = false
                beginCustomEdit()
            }
        }
    }

    private var customDisplayLabel: String {
        isCustomValue ? "\(formatted(value))s" : t("custom")
    }

    private func intervalButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected
                    ? ((controlActiveState == .inactive || !isEnabled) ? Color(nsColor: .unemphasizedSelectedTextColor) : NeManeemTheme.accentForeground)
                    : (isEnabled ? Color.primary : Color(nsColor: .disabledControlTextColor)))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: settingsCompactSegmentContentHeight)
                .background(selected
                    ? ((controlActiveState == .inactive || !isEnabled) ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : NeManeemTheme.accent)
                    : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
    }

    private func isSelected(_ preset: Double) -> Bool {
        followsMenuBar?.wrappedValue != true && !editingCustom && abs(value - preset) < 0.001
    }

    private var isCustomValue: Bool {
        !presets.contains { abs($0 - value) < 0.001 }
    }

    private func choosePreset(_ preset: Double) {
        followsMenuBar?.wrappedValue = false
        if isCustomValue { lastCustomValue = value }
        editingCustom = false
        invalidCustom = false
        customFieldFocused = false
        customText = ""
        value = SettingsStore.normalizeInterval(preset)
    }

    private func beginCustomEdit() {
        let initial = isCustomValue ? value : (lastCustomValue ?? value)
        customText = formatted(initial)
        invalidCustom = false
        editingCustom = true
        DispatchQueue.main.async {
            customFieldFocused = true
            nmSelectAllCurrentTextEditor()
        }
    }

    private func cancelCustomEdit() {
        customText = ""
        invalidCustom = false
        editingCustom = false
        customFieldFocused = false
    }

    private func commit() {
        guard editingCustom else { return }
        guard let parsed = SettingsStore.parseIntervalText(customText) else {
            invalidCustom = true
            customFieldFocused = true
            return
        }
        value = parsed
        lastCustomValue = parsed
        customText = ""
        invalidCustom = false
        editingCustom = false
        customFieldFocused = false
    }

    private func formatted(_ seconds: Double) -> String {
        if abs(seconds.rounded() - seconds) < 0.001 {
            return String(Int(seconds.rounded()))
        }
        return String(format: "%.1f", seconds)
    }
}

struct LowActivityThresholdEditor: View {
    let title: String
    @Binding var durationValue: Double
    @Binding var durationUnit: LowActivityDurationUnit
    @Binding var dataValue: Double
    @Binding var dataUnit: LowActivityDataUnit
    let t: (String) -> String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 10)
                controls
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            TextField("", value: durationBinding, format: .number.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .nmSelectAllOnEdit()
            Picker("", selection: $durationUnit) {
                Text(t("minutes")).tag(LowActivityDurationUnit.minutes)
                Text(t("hours")).tag(LowActivityDurationUnit.hours)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 68)

            Text(t("during"))
                .foregroundStyle(.secondary)
                .fixedSize()

            TextField("", value: dataBinding, format: .number.precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
                .nmSelectAllOnEdit()
            Picker("", selection: $dataUnit) {
                ForEach(LowActivityDataUnit.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 72)

            Text(t("orLess"))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { durationValue },
            set: { durationValue = SettingsStore.normalizeLowActivityDuration($0) }
        )
    }

    private var dataBinding: Binding<Double> {
        Binding(
            get: { dataValue },
            set: { dataValue = SettingsStore.normalizeLowActivityData($0) }
        )
    }
}


struct NumericAdjuster: View {
    let title: String
    var help: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(title)
                Spacer()
                Button { adjust(-step) } label: { Image(systemName: "minus") }
                    .buttonStyle(NMUtilityIconButtonStyle())
                TextField("", value: $value, format: .number.precision(.fractionLength(decimals)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .onSubmit { clamp() }
                    .nmSelectAllOnEdit()
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                Button { adjust(step) } label: { Image(systemName: "plus") }
                    .buttonStyle(NMUtilityIconButtonStyle())
            }
            if let help {
                SettingsHelpText(help)
            }
        }
    }

    private func adjust(_ delta: Double) {
        value = min(range.upperBound, max(range.lowerBound, value + delta))
    }

    private func clamp() {
        value = min(range.upperBound, max(range.lowerBound, value))
    }
}
