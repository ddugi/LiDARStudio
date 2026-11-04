# Known issues and verification status

Copyright © 2026 Dugi Selmanaj. All rights reserved.

Last updated: 2026-11-04.

This register separates confirmed evidence from hypotheses. A passing build is
not evidence that a camera, LiDAR, reconstruction, or persistence workflow has
passed on physical hardware.

## P0 — RealityKit Object Capture Metal assertion

Status: **reproduced in production and the isolated minimal application**.

After `ObjectCaptureSession.startDetecting()` returns `true` and RealityKit
enters detection, Metal API Validation can abort in:

```text
re::MeshShadowGenerateMipmapNode::execute
Compute Function(meshShadowCalculateMip):
missing Threadgroup Memory binding at index 0 for perPixelData[0]
```

The matching minimal reproduction makes a RealityKit/framework-level defect a
strong suspicion. Metal validation remains enabled and no undocumented
workaround is used. See
`Diagnostics/ObjectCaptureMinimalRepro/FEEDBACK.md` for the captured evidence.

Impact: stable Object Studio detection and a complete real-device capture are
not verified.

## P0 — ARKit tracking does not become normal

Status: **confirmed in three debugger/device-hub Basic runs; root cause unknown**.

Observed Basic results on Dösti, iPhone 18 Pro, iOS 27.2:

| Run | ARFrame callbacks | Normal tracking frames | Start/Stop |
| --- | ---: | ---: | --- |
| 1 | 2,055 | 0 | Pass |
| 2 | 1,686 | 0 | Pass |
| 3 | 3,276 | 0 | Pass |

The UI remained responsive and no crash or watchdog was observed. Tracking
remained `initializing` or `notAvailable`. Repeated `FigCaptureSourceRemote`
errors `-12784` and `-12710` were present. These errors correlate with the
failure but do not establish causality.

After a device restart, attempts to run an unscreen-mirrored Basic test did not
produce a valid Basic evidence run because the RGB-D action was selected instead.
Therefore the fully isolated post-restart comparison remains **not tested**.

## P0 — No verified live scene depth dataset

Status: **failed physical acceptance test**.

The bounded RGB-D recorder received 2,257 ARKit callbacks but accepted zero
samples because neither `sceneDepth` nor `smoothedSceneDepth` was present:

- RGB-D samples accepted: 0
- RGB frames written: 0
- depth frames written: 0
- confidence maps written: 0

The empty manifest was correctly rejected. No dataset success is claimed.
Depth and recording tests must not resume until Basic tracking reaches normal.

## Incomplete product areas

- Room Studio has capability UI but no integrated RoomPlan capture engine.
- Environment Studio is an isolated diagnostic/RGB-D proof of concept, not a
  saved environment reconstruction workflow.
- End-to-end textured USDZ production, persistence, reopen, and sharing have not
  completed a stable representative physical-device acceptance run.
- Public CI performs an unsigned simulator build on GitHub's `xcode-27` runner.
  The locally passing full test suite is not yet executed by the required
  hosted CI check.
- Product naming says LiDARStudio 2.0 while `MARKETING_VERSION` remains `0.1.0`.
  Version changes require an explicit release decision.

## Next evidence gate

1. Run Basic ARKit for 30 seconds after a device restart without debugger or
   live screen mirroring.
2. Confirm non-nil camera images, valid intrinsics/transforms, and a complete
   tracking-state timeline.
3. Require at least one `normal` tracking frame before enabling Depth.
4. Compare the same device with a minimal documented ARKit sample.
5. Collect sysdiagnose only when needed and never commit private sensor data.
