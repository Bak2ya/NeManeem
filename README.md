# NeManeem

NeManeem is a macOS menu-bar utility for monitoring network usage, reviewing per-app traffic, recording usage history, managing data limits, and optionally controlling app network access.

**Current public-source candidate:** v1.1.0 · Build 145  
**Requires:** macOS 13 or later

[View on App Store](https://apps.apple.com/app/id6806773845)

## Highlights

- Live download/upload speed in the menu bar
- Per-app network usage and optional app network control
- Usage history, sessions, summaries, CSV/Excel export
- Data-limit management for all networks or a selected network
- Customizable popover/monitor layouts and resource modes
- App/process information with Finder reveal and optional local display grouping
- Korean, English, Japanese, and Spanish interface

## Privacy

NeManeem is designed around local processing.

- Usage data is stored on the Mac.
- The macOS Location permission is used only when needed to identify the current Wi-Fi name (SSID) for network-specific features. Geographic coordinates are not stored or transmitted by NeManeem.
- Diagnostic reports are created only when the user explicitly requests them and can be reviewed before sending.

See [PRIVACY.md](PRIVACY.md) for details.

## Version 1.1

Version 1.1 focuses on performance, clarity, stability, and accessibility:

- Faster handling of large observed-app lists and more efficient long-running usage recording
- Reorganized Usage settings, clearer session/data management, and expanded export choices
- Shared app/process information and Finder actions across Network and Usage views
- Improved Settings, native popover preview, keyboard navigation, and accessibility behavior
- Safer Host ↔ Network Extension liveness/fail-open handling for blocking features
- Refined selection/accent behavior across Settings

See [RELEASE_NOTES_v1.1.0.md](RELEASE_NOTES_v1.1.0.md) for the release summary.

## Build

Open `NeManeem.xcodeproj` in Xcode. The project contains both the host app and its Network System Extension.

Because Network/System Extension capabilities require Apple signing and entitlements, contributors building under another developer account may need to select their own signing team and provision the required capabilities.

See [BUILDING.md](BUILDING.md) for a concise build overview.

## Source layout

- `App/` — host app plist and entitlements
- `SystemExtension/` — Network System Extension / content filter provider
- `Shared/` — models, services, UI, and utilities shared by the app
- `Resources/` — app icon and runtime assets
- `Scripts/` — validation and release-check helpers

## Repository

Public repository: https://github.com/Bak2ya/NeManeem
