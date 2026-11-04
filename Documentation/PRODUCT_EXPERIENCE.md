# Product experience inventory

Copyright © 2026 Dugi Selmanaj. All rights reserved.

Status: Product Experience sprint implementation, 2026-11-04.

This inventory describes non-capture application behavior. It does not claim
that Object Capture, RoomPlan, ARKit tracking, LiDAR depth, or reconstruction
has passed physical acceptance testing.

| Area | Before | After this sprint |
| --- | --- | --- |
| Home | Four static navigation cards | Repository scan count, up to three real recent projects, capability status, settings and typed navigation |
| Library | Basic list, viewer link, swipe metadata deletion | Searchable adaptive grid, sort, favorites, previews, details, rename, explicit destructive confirmation, share and reliable states |
| Persistence | Versioned local metadata and secure USDZ lookup | Backward-compatible favorite metadata, validated preview/capture paths, storage usage and selected asset deletion |
| Viewer | Quick Look and share button | USDZ preflight validation, clear missing/invalid errors, native interaction, file name/format/size and Share Sheet |
| Onboarding | None | Three-page first-launch explanation covering workflow separation, local privacy and camera permission timing |
| Settings | About screen only | Storage, version/build, public-API hardware capabilities, permission state, diagnostics access, privacy and ownership |
| Navigation | Direct SwiftUI links | Typed top-level destinations with testable navigation state |
| Tests | Models, capture state, persistence and RGB-D structure | Added CRUD, rename, favorites, search/sort, deletion, validation, migration, navigation and empty/error tests |

## Preserved boundaries

- No `ObjectCaptureSession` lifecycle, `ARSession` configuration, or RealityKit
  rendering code was changed.
- No local scan, photo, or dataset was deleted during development or validation.
- Signing, bundle identifiers, license, ownership, and IP documentation remain
  unchanged.
- Room Studio and Environment Studio capture behavior remain as implemented
  before this sprint.

## Validation boundary

The signed application was built, installed over the existing app, and launched
on Dösti. Manual touch, Dynamic Type, VoiceOver, search, rename, deletion,
Quick Look gestures, Share Sheet, and relaunch persistence still require direct
physical-device acceptance testing.
