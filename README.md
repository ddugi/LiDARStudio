# LiDARStudio

LiDARStudio is a native SwiftUI research and development application for local
3D scanning workflows on supported Apple devices. The project separates Object
Capture, RoomPlan, ARKit environment diagnostics, and the local scan library.

Copyright © 2026 Dugi Selmanaj. All rights reserved.

## Current status

LiDARStudio is under active development. The repository name refers to the
LiDARStudio 2.0 product effort; the current app marketing version remains
`0.1.0` and is not a public App Store release.

| Area | Implemented in source | Physical-device evidence |
| --- | --- | --- |
| Object Studio guided capture | Yes | Starts on the target device; detection remains blocked by a reproduced RealityKit Metal assertion |
| Object photogrammetry and USDZ workflow | Yes | End-to-end textured reconstruction is not yet verified on the target device |
| Room Studio | Foundation UI and capability check | Scanner integration not complete |
| Environment Studio | Isolated ARKit diagnostics and bounded RGB-D recorder | ARFrame callbacks observed; normal tracking and live depth remain unverified |
| My Scans | Local metadata, USDZ validation, viewer, and sharing | Three repository tests currently expose an iOS path-normalization regression |

See [Known Issues](Documentation/KNOWN_ISSUES.md) before interpreting any
hardware-dependent feature as complete.

## Requirements

- Xcode 27.0 or a compatible newer toolchain.
- An iPhone supported by the Apple APIs used by the selected workflow.
- A LiDAR-equipped supported device for scene depth, mesh reconstruction, and
  RoomPlan capability.
- A locally configured Apple Development team for physical-device builds.

The project preserves automatic signing but does not include certificates,
private keys, provisioning profiles, or Apple account credentials.

## Build and test

Authorized maintainers can build the main scheme with Xcode or `xcodebuild`:

```sh
xcodebuild \
  -project iDARStudio.xcodeproj \
  -scheme iDARStudio \
  -configuration Debug \
  -destination 'id=<DEVICE_UDID>' \
  -allowProvisioningUpdates \
  build
```

Run automated tests on an unlocked configured device by replacing `build` with
`test`. Hardware behavior must be validated separately; automated tests do not
simulate camera, LiDAR, Object Capture, or photogrammetry success.

## Architecture and documentation

- [Application architecture](Documentation/ARCHITECTURE.md)
- [Architecture decision records](Documentation/adr/README.md)
- [Testing and evidence policy](Documentation/TESTING.md)
- [Known issues](Documentation/KNOWN_ISSUES.md)
- [Privacy and local data](PRIVACY.md)
- [Security policy](SECURITY.md)
- [RGB-D dataset format](Documentation/RGBDDatasetFormat.md)
- [Third-party dependency register](Documentation/THIRD_PARTY_DEPENDENCIES.md)
- [Research knowledge base](docs/research/rvp/publication-index.md)
- [Change log](CHANGELOG.md)

## License and ownership

This public repository is **proprietary source-available software, not open
source**. Public visibility permits inspection only and does not grant rights to
use, copy, modify, distribute, commercialize, or create derivative works.

See [LICENSE](LICENSE) for the controlling terms. LiDARStudio branding, the app
icon, designs, documentation, workflows, and source code remain reserved to
Dugi Selmanaj except where a separate written agreement states otherwise.

## Development status

The project contains experimental hardware workflows. A passing build does not
establish that Object Capture, LiDAR depth, reconstruction, or other physical
device behavior is complete. Hardware-dependent results are documented as
verified, failed, or untested and are never simulated.

Known platform investigation material is kept under `Diagnostics/`. Local scan
photos, RGB-D datasets, USDZ files, certificates, provisioning profiles, and
developer user state must not be committed.

## Dependencies

The application currently uses Apple platform frameworks and contains no
third-party packages or copied third-party source. See
[Documentation/THIRD_PARTY_DEPENDENCIES.md](Documentation/THIRD_PARTY_DEPENDENCIES.md).

## Contributions

Unsolicited code or asset contributions are not currently accepted. See
[CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
