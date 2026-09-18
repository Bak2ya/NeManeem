# Building NeManeem

## Requirements

- macOS 13 or later
- A recent Xcode release capable of building the included project
- An Apple development team with the capabilities required by the host app and Network System Extension

## Open and build

1. Open `NeManeem.xcodeproj` in Xcode.
2. Review Signing & Capabilities for both `NeManeem` and `NeManeemFilter`.
3. If you are not building with the original signing team, select your own development team and provision the required App Group / Network Extension / System Extension capabilities.
4. Build the project in Xcode.

For real Network System Extension testing, macOS may require the signed app to run from `/Applications` and may require explicit approval in System Settings.

## Important capabilities

The host app uses App Sandbox, user-selected file access, System Extension installation, Network Extension content filtering, an App Group, and Location permission for Wi-Fi SSID identification.

The embedded System Extension uses App Sandbox, Network Extension content filtering, and the same App Group.

## Validation helpers

The repository includes check-only scripts used during development, including `VERIFY_PROJECT.command`, `APP_STORE_PREFLIGHT.command`, and `SHOW_APP.command`. Some checks are macOS/Xcode-specific.

These scripts do not replace real signed runtime testing of System Extension installation, XPC communication, permissions, or traffic filtering.
