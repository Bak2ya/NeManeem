import SwiftUI

// Shared explanation grammar for every settings page. Keeping these views
// separate prevents page implementation order from being mixed with the
// essential/detail description policy.

enum SettingsDescriptionLevel {
    case essential
    case detail
}

struct SettingsHelpText: View {
    let text: String
    let level: SettingsDescriptionLevel
    @AppStorage("general.showDetailedDescriptions") private var showDetailedDescriptions = false

    init(_ text: String, level: SettingsDescriptionLevel = .essential) {
        self.text = text
        self.level = level
    }

    @ViewBuilder var body: some View {
        if level == .essential || showDetailedDescriptions {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let help: String?
    let helpLevel: SettingsDescriptionLevel
    let detailHelp: String?

    init(_ title: String, help: String? = nil, helpLevel: SettingsDescriptionLevel = .essential, detailHelp: String? = nil) {
        self.title = title
        self.help = help
        self.helpLevel = helpLevel
        self.detailHelp = detailHelp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if let help, !help.isEmpty {
                SettingsHelpText(help, level: helpLevel)
            }
            if let detailHelp, !detailHelp.isEmpty {
                SettingsHelpText(detailHelp, level: .detail)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsItemWithHelp<Content: View>: View {
    let help: String
    let helpLevel: SettingsDescriptionLevel
    let detailHelp: String?
    let content: Content

    init(_ help: String, helpLevel: SettingsDescriptionLevel = .essential, detailHelp: String? = nil, @ViewBuilder content: () -> Content) {
        self.help = help
        self.helpLevel = helpLevel
        self.detailHelp = detailHelp
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            SettingsHelpText(help, level: helpLevel)
            if let detailHelp, !detailHelp.isEmpty {
                SettingsHelpText(detailHelp, level: .detail)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsActionRow: View {
    let title: String
    let help: String?
    let helpLevel: SettingsDescriptionLevel
    let detailHelp: String?
    let buttonTitle: String
    let action: () -> Void

    init(_ title: String, help: String? = nil, helpLevel: SettingsDescriptionLevel = .essential, detailHelp: String? = nil, buttonTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.helpLevel = helpLevel
        self.detailHelp = detailHelp
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let help, !help.isEmpty {
                    SettingsHelpText(help, level: helpLevel)
                }
                if let detailHelp, !detailHelp.isEmpty {
                    SettingsHelpText(detailHelp, level: .detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(buttonTitle, action: action)
                .buttonStyle(NMNeutralActionButtonStyle())
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
    }
}

