import AppKit
import SwiftUI

// MARK: - NeManeem UI Rule Pack

/// Shared visual rules for settings-window controls.
///
/// The settings shell keeps the app accent for stateful controls such as toggles,
/// sliders, selected values and the sidebar. Selected values follow the configured
/// accent; inactive/disabled selections stay neutral. Ordinary action buttons are neutral
/// by default. Only an action that confirms a workflow uses the primary accent, and
/// destructive actions opt into the destructive style explicitly.
enum NMUIRulePack {
    static let actionCornerRadius: CGFloat = 7
    static let navigationCornerRadius: CGFloat = 9
}

/// Default settings-window button. This is intentionally independent of `.tint`, so
/// adding a new ordinary Button does not silently turn it into a primary blue action.
struct NMNeutralActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let windowIsActive = activeState != .inactive
        let foreground = isEnabled
            ? (windowIsActive ? Color.primary : Color.secondary)
            : Color(nsColor: .disabledControlTextColor)
        let backgroundOpacity: Double
        if !isEnabled {
            backgroundOpacity = 0.16
        } else if configuration.isPressed {
            backgroundOpacity = windowIsActive ? 0.72 : 0.48
        } else {
            backgroundOpacity = windowIsActive ? 0.54 : 0.34
        }

        return configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                    .opacity(backgroundOpacity),
                in: RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(isEnabled ? 0.48 : 0.18), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.72)
    }
}

/// A workflow-confirming action such as Schedule, Apply or Export Selected.
struct NMPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let emphasized = isEnabled && activeState != .inactive
        let fill = emphasized
            ? NeManeemTheme.accent.opacity(configuration.isPressed ? 0.78 : 1)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        let foreground = emphasized
            ? NeManeemTheme.accentForeground
            : Color(nsColor: .unemphasizedSelectedTextColor)

        return configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(fill, in: RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(emphasized ? 0.22 : 0.34), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.68)
    }
}

/// Entry/preparation action for something potentially destructive. It keeps the
/// ordinary neutral button surface but uses red text/border so risk is visible
/// without competing with the final destructive confirmation. The final action in
/// a confirmation dialog continues to use `NMDestructiveActionButtonStyle` or the
/// native destructive role.
struct NMDestructiveSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && activeState != .inactive
        let foreground = active ? Color.red : Color(nsColor: .disabledControlTextColor)
        let fillOpacity: Double
        if !isEnabled {
            fillOpacity = 0.12
        } else if configuration.isPressed {
            fillOpacity = active ? 0.16 : 0.10
        } else {
            fillOpacity = active ? 0.04 : 0.02
        }

        return configuration.label
            .fontWeight(.medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Color.red.opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous)
                    .stroke(Color.red.opacity(active ? 0.34 : 0.12), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.68)
    }
}

/// Visible destructive action. Confirmation-dialog buttons continue to use the
/// native `role: .destructive` presentation supplied by macOS.
struct NMDestructiveActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let emphasized = isEnabled && activeState != .inactive
        let fill = emphasized
            ? Color.red.opacity(configuration.isPressed ? 0.70 : 0.88)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        let foreground = emphasized ? Color.white : Color(nsColor: .unemphasizedSelectedTextColor)

        return configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(fill, in: RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous)
                    .stroke(Color.red.opacity(emphasized ? 0.28 : 0.12), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: NMUIRulePack.actionCornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.68)
    }
}

/// Window-chrome navigation control used beside the traffic-light area.
struct NMNavigationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && activeState != .inactive
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .frame(width: 28, height: 28)
            .background(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(configuration.isPressed ? 0.98 : (active ? 0.82 : 0.46)),
                in: RoundedRectangle(cornerRadius: NMUIRulePack.navigationCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NMUIRulePack.navigationCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(active ? 0.42 : 0.22), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: NMUIRulePack.navigationCornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.62)
    }
}

/// Compact icon-only adjustment button such as plus/minus.
struct NMUtilityIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && activeState != .inactive
        return configuration.label
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .frame(width: 26, height: 24)
            .background(
                Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                    .opacity(configuration.isPressed ? 0.72 : (active ? 0.46 : 0.24)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(active ? 0.42 : 0.18), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isEnabled ? 1 : 0.62)
    }
}

/// Compact text or icon action used inside a popover/status surface. It stays
/// neutral even when the surrounding surface carries the app accent for stateful
/// controls. This is the flat counterpart of `NMNeutralActionButtonStyle`.
struct NMInlineActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityShowBorders) private var showBorders

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && activeState != .inactive
        return configuration.label
            .foregroundStyle(active ? Color.primary : Color(nsColor: .disabledControlTextColor))
            .padding(.horizontal, showBorders ? 5 : 0)
            .padding(.vertical, showBorders ? 3 : 0)
            .overlay {
                if showBorders {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.62 : (isEnabled ? 1 : 0.58))
            .contentShape(Rectangle())
    }
}

/// Borderless destructive icon, used for compact trash controls.
struct NMDestructiveIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityShowBorders) private var showBorders

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.red : Color(nsColor: .disabledControlTextColor))
            .padding(.horizontal, showBorders ? 5 : 0)
            .padding(.vertical, showBorders ? 3 : 0)
            .overlay {
                if showBorders {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.red.opacity(isEnabled ? 0.65 : 0.25), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.62 : (isEnabled ? 1 : 0.58))
            .contentShape(Rectangle())
    }
}

private struct NMDisplaySizeStepButtonStyle: ButtonStyle {
    let font: Font
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && activeState != .inactive
        return configuration.label
            .font(font)
            .foregroundStyle(active ? Color.secondary : Color(nsColor: .disabledControlTextColor))
            .frame(width: 22, height: 26)
            .background(
                Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                    .opacity(configuration.isPressed ? 0.66 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isEnabled ? 1 : 0.58)
    }
}

/// AppKit-backed slider used by the shared display-size editor.
/// SwiftUI's macOS Slider can reserve layout space that is not occupied by the
/// visible track. NSSlider keeps the view frame and visible track adjacent, so
/// the small/large A buttons can sit next to the actual control rather than an
/// invisible layout slot.
private struct NMDisplaySizeSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range, step: step)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.tickMarkPosition = .below
        slider.numberOfTickMarks = tickCount
        slider.allowsTickMarkValuesOnly = true
        slider.altIncrementValue = step
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.range = range
        context.coordinator.step = step
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.numberOfTickMarks = tickCount
        slider.altIncrementValue = step
        if abs(slider.doubleValue - value) > 0.000_1 {
            slider.doubleValue = value
        }
    }

    private var tickCount: Int {
        max(2, Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1)
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var range: ClosedRange<Double>
        var step: Double

        init(value: Binding<Double>, range: ClosedRange<Double>, step: Double) {
            self.value = value
            self.range = range
            self.step = step
        }

        @objc func valueChanged(_ sender: NSSlider) {
            let raw = min(range.upperBound, max(range.lowerBound, sender.doubleValue))
            let offset = ((raw - range.lowerBound) / step).rounded() * step
            let snapped = min(range.upperBound, max(range.lowerBound, range.lowerBound + offset))
            sender.doubleValue = snapped
            value.wrappedValue = snapped
        }
    }
}

/// Shared display-size editor for Menu Bar, Popover and Monitor settings.
/// The A buttons are real step controls: small A decrements one step and large A
/// increments one step, while the slider and point-size label stay synchronized.
struct NMDisplaySizeControl: View {
    let title: String
    let resetTitle: String
    let smallerHelp: String
    let largerHelp: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let pointSize: (Double) -> Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 12)

                // The AppKit slider is the actual visible control: there is no
                // hidden flexible SwiftUI Slider slot between the A and the track.
                HStack(spacing: 4) {
                    Button { adjust(by: -step) } label: { Text("A") }
                        .buttonStyle(NMDisplaySizeStepButtonStyle(font: .caption2))
                        .disabled(value <= range.lowerBound + step / 2)
                        .help(smallerHelp)
                        .accessibilityLabel(smallerHelp)

                    NMDisplaySizeSlider(value: $value, range: range, step: step)
                        .frame(width: 260, height: 28)

                    Button { adjust(by: step) } label: { Text("A") }
                        .buttonStyle(NMDisplaySizeStepButtonStyle(font: .title2))
                        .disabled(value >= range.upperBound - step / 2)
                        .help(largerHelp)
                        .accessibilityLabel(largerHelp)

                    Text(String(format: "%.1f pt", pointSize(value)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }
            }

            HStack {
                Spacer()
                Button(resetTitle) { value = defaultValue }
                    .buttonStyle(NMNeutralActionButtonStyle())
            }
        }
    }

    private func adjust(by delta: Double) {
        let candidate = min(range.upperBound, max(range.lowerBound, value + delta))
        let snapped = (candidate / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}
