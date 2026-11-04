# LiDARStudio Engineering Instructions

## Ownership and intellectual property

- Product owner and intended personal IP owner: **Dugi Selmanaj**.
- Copyright: **© 2026 Dugi Selmanaj. All rights reserved.**
- Treat all source code, designs, product concepts, scan workflows, assets, and documentation in this repository as proprietary. Repository contents may be publicly viewable, but public access does not grant permission to use, copy, modify, or redistribute them.
- Do not relicense, publish, redistribute, or copy project material into another product without Dugi Selmanaj's written authorization.
- The repository is source-available, not open source. Preserve the root `LICENSE`, copyright notices, branding restrictions, and contribution policy.

## Engineering rules

- Build the product as a native SwiftUI iPhone application.
- Keep Object Capture, RoomPlan, and ARKit scene-reconstruction engines in separate modules or feature boundaries.
- A single coordinator must own camera-session access. Never run competing camera or AR sessions.
- Do not fabricate scans, meshes, previews, measurements, or successful hardware results.
- Keep scans and their metadata on device by default. Any future upload or sharing flow must be explicit and user initiated.
- Preserve signing, bundle identifiers, entitlements, and team settings unless the product owner explicitly requests a change.
- Prefer Apple-supported public APIs and document every third-party dependency and its license.
- Keep UI accessible: support Dynamic Type, VoiceOver labels, sufficient contrast, and at least 44-point interactive targets.
- Add automated tests for models, persistence, state transitions, and other non-hardware logic.
- Hardware features are incomplete until integrated on a supported physical device and verified with representative captures.

## Validation expectations

- Build with `xcodebuild` after meaningful changes.
- Run all available automated tests.
- Report simulator limitations and remaining physical-device tests honestly.
