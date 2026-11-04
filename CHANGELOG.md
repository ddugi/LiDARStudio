# Changelog

All notable repository changes are recorded here. Dates describe repository
work, not App Store releases.

## Unreleased

### Documentation and governance

- Added current-state application architecture and architecture decisions.
- Added known-issues, testing, privacy, and security policies.
- Added GitHub ownership and structured issue templates.
- Expanded README status, requirements, build instructions, and document index.

## 0.1.0 development line

### Application foundation

- Added the premium SwiftUI shell, four main product sections, design system,
  capability checks, local scan metadata, repository, states, About screen, and
  proprietary IP documentation.

### Object Studio

- Added an Object Capture workflow, serialized detection lifecycle, guided
  multi-distance stages, review, on-device photogrammetry integration, USDZ
  validation, local library integration, viewer, sharing, and cancellation.
- Added an isolated Object Capture minimal reproduction for the confirmed
  RealityKit/Metal validation assertion.

### Environment and RGB-D research

- Added Basic, Depth, and Mesh ARKit diagnostic stages.
- Added a bounded local RGB-D recorder, versioned manifest, validator, Mac
  validation tool, and automated structural tests.
- Added the RVP research inventory, feasibility analysis, experiments, and
  research architecture.

### UX and reliability

- Added a centralized reference-counted screen-awake manager.
- Added the supplied LiDARStudio app icon and About-screen icon reuse.
- Added real framework-derived progress labels and compact capture controls.

### Known limitations

- Object Capture detection is blocked by a reproduced RealityKit Metal
  assertion on the tested platform.
- ARKit normal tracking and live scene depth are not yet verified.
- Three local repository tests expose an unresolved iOS path-normalization
  regression.
