# LiDARStudio

LiDARStudio is a native SwiftUI research and development application for local
3D scanning workflows on supported Apple devices. The project separates Object
Capture, RoomPlan, ARKit environment diagnostics, and the local scan library.

Copyright © 2026 Dugi Selmanaj. All rights reserved.

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
