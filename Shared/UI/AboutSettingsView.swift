import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

private struct ManeemMoment: Equatable {
    let assetName: String
    let captionKey: String
}

struct AboutSettingsView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @State private var maneemMoment: ManeemMoment?
    @State private var lastManeemAssetName: String?
    @State private var showBuildNumber = false

    private var t: (String) -> String { { L10n.text($0, language: settings.language) } }

    // Public source and App Store destinations are explicit user-invoked links.
    // The App Store link uses the permanent App Store Connect Apple ID.
    private let githubURL = URL(string: "https://github.com/Bak2ya/NeManeem")!
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6806773845")
    private let privacyPolicyURL = URL(string: "https://github.com/Bak2ya/NeManeem/blob/main/PRIVACY.md")!

    private let maneemAssets = [
        "Maneem_5572", "Maneem_5147", "Maneem_5142", "Maneem_5128",
        "Maneem_5104", "Maneem_4994", "Maneem_4892", "Maneem_4779",
        "Maneem_4749", "Maneem_4016", "Maneem_3339", "Maneem_3276",
        "Maneem_2431", "Maneem_2121"
    ]

    private let randomManeemCaptionKeys = [
        "easterData", "easterOwner", "easterTreats", "easterNap",
        "easterInternalCat", "easterFur", "easterLocal", "easterStatus"
    ]

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard showBuildNumber else {
            return "\(t("version")) \(version)"
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(t("version")) \(version) · Build \(build)"
    }

    var body: some View {
        ZStack {
            aboutContent

            if let maneemMoment {
                maneemOverlay(maneemMoment)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: maneemMoment)
        .onDisappear {
            maneemMoment = nil
            showBuildNumber = false
        }
    }

    private var aboutContent: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 455
            let sectionSpacing: CGFloat = compact ? 6 : 8
            let dividerPadding: CGFloat = compact ? 7 : 11
            let edgeSpacing: CGFloat = compact ? 4 : 10
            let iconSize: CGFloat = compact ? 57 : 65

            VStack(spacing: 0) {
                Spacer(minLength: edgeSpacing)

                VStack(spacing: compact ? 4 : 6) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)

                    Text("NeManeem")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                        .onTapGesture(count: 2) {
                            revealManeem()
                        }
                        .accessibilityAction(named: Text(t("revealManeemAccessibility"))) {
                            revealManeem()
                        }

                    Text(t("nameOrigin"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)

                }

                Divider()
                    .frame(maxWidth: 420)
                    .padding(.vertical, dividerPadding)

                VStack(spacing: sectionSpacing) {
                    Text(t("privacyPromise"))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("privacyCompact"))
                        Text(t("privacyLocationUse"))
                        Text(t("privacyDiagnosticTransfer"))
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)

                    Text(t("verifyWithAI"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)

                    Link(t("privacyPolicy"), destination: privacyPolicyURL)
                        .font(.callout)
                }

                Divider()
                    .frame(maxWidth: 420)
                    .padding(.vertical, dividerPadding)

                VStack(spacing: sectionSpacing) {
                    // Intentionally Korean in every app language: this is the creator's signature.
                    Text("이 앱은 마님이와 Bak2YA가 ChatGPT와 함께 만들었습니다.")
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    VStack(spacing: 8) {
                        releaseLinkButton(imageName: "GitHubInvertocat", title: t("viewOnGitHub"), url: githubURL)
                        releaseLinkButton(systemName: "apple.logo", title: t("viewOnAppStore"), url: appStoreURL)
                        Button {
                            _ = TroubleshootingService.composeSupportEmail()
                        } label: {
                            Label(t("contactSupport"), systemImage: "envelope")
                        }
                        .buttonStyle(NMNeutralActionButtonStyle())
                    }

                    Text(versionText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showBuildNumber.toggle()
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            showBuildNumber.toggle()
                        }
                        .padding(.top, compact ? 1 : 3)

                    Text(t("maneemEasterHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                }

                Spacer(minLength: edgeSpacing)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, compact ? 4 : 8)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func revealManeem() {
        let available = maneemAssets.filter { $0 != lastManeemAssetName }
        let candidates = available.isEmpty ? maneemAssets : available
        guard let assetName = candidates.randomElement() else { return }

        let captionKey: String
        if assetName == "Maneem_5142" || assetName == "Maneem_5147" {
            captionKey = "easterBuildMoment"
        } else {
            captionKey = randomManeemCaptionKeys.randomElement() ?? "easterData"
        }

        lastManeemAssetName = assetName
        let moment = ManeemMoment(assetName: assetName, captionKey: captionKey)
        maneemMoment = moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard maneemMoment == moment else { return }
            withAnimation(.easeOut(duration: 0.3)) { maneemMoment = nil }
        }
    }

    private func maneemOverlay(_ moment: ManeemMoment) -> some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                Text(t("easterFound"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Image(moment.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: max(220, geo.size.width - 42),
                        maxHeight: max(190, geo.size.height - 112)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(t(moment.captionKey))
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: max(220, geo.size.width - 52))
            }
            .padding(16)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                maneemMoment = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func releaseLinkButton(systemName: String, title: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: systemName)
            }
            .buttonStyle(NMNeutralActionButtonStyle())
        } else {
            Button { } label: {
                Label(title, systemImage: systemName)
            }
            .buttonStyle(NMNeutralActionButtonStyle())
            .disabled(true)
            .help(t("releaseLinkPending"))
        }
    }

    private func releaseLinkButton(imageName: String, title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(imageName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(title)
            }
        }
        .buttonStyle(NMNeutralActionButtonStyle())
    }
}

// MARK: - Shared Settings Components

