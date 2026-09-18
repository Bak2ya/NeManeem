# Building NeManeem

NeManeem is a native Mac app with a bundled Network Extension / System Extension.

## Requirements

- A Mac running a supported version of macOS
- A recent version of Xcode
- macOS 13.0 or later as the deployment target
- An Apple Developer account if you want to run the extension-backed features locally

The repository does not rely on a third-party package manager for the app targets.

## Open the project

1. Clone this repository.
2. Open `NeManeem.xcodeproj` in Xcode.
3. Select the `NeManeem` scheme.
4. Review Signing & Capabilities for both targets:
   - `NeManeem`
   - `NeManeemFilter`
5. Select your own development team before building locally.

## Signing and capabilities

The public project includes the source and entitlement declarations used by NeManeem, but Apple provisioning is tied to the developer account that owns the identifiers and capabilities.

The host app uses capabilities including:

- App Sandbox
- App Groups
- System Extension installation
- Network Extension content filtering
- Location permission for optional Wi-Fi SSID identification

The bundled filter target also uses the Network Extension content-filter capability and the shared App Group.

If you are building under a different Apple Developer account, you may need to substitute your own bundle identifiers, App Group identifiers, signing team, and provisioning profiles consistently across the project.

Without the appropriate Apple-granted capabilities and provisioning, the source can still be inspected and parts of the project may compile, but the System Extension / content-filter functionality may not install or run.

## Build

With signing configured:

1. Select the `NeManeem` scheme.
2. Choose **Product → Build** in Xcode.
3. Run the app from Xcode.

On first use of extension-backed features, macOS may ask you to approve the required System Extension or permissions.

## App Store build

The App Store release uses the maintainer's distribution signing and provisioning. Those credentials and profiles are intentionally not included in this repository.
