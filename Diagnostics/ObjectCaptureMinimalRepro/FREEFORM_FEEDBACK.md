# RealityKit Object Capture Freeform SIGTRAP

Proprietary diagnostic material. Copyright © 2026 Dugi Selmanaj. All rights reserved.

## Environment

- Xcode 27.0 (27A266a), iOS 27.0 SDK
- iOS 27.3 beta (24C5037i)
- iPhone 18 Pro (`iPhone19,2`, arm64e.x1)
- Developer Mode enabled; device unlocked
- Metal API Validation left enabled
- Production bundle: `se.dugiselmanaj.lidarstudio2`
- Isolated bundle: `se.dugiselmanaj.lidarstudio2.objectcapture-repro`
- Production source revision: `f96fe0e`
- `_RealityKit_SwiftUI` UUID: `ED91507A-4D97-3893-850E-A442CEFEF3C1`

## Production reproduction

1. Create one `ObjectCaptureSession` and mount Apple's `ObjectCaptureView`.
2. Call `start(imagesDirectory:configuration:)` once.
3. Wait for the framework to report `ready`.
4. After object detection returns the recoverable no-surface result, invoke
   `startCapturing()` once from the same ready session.
5. The application terminates synchronously on the main thread.

Production crash report: `iDARStudio-2026-11-15-190732.ips`.

## Isolated reproduction

The existing minimal target was launched with `--auto-freeform`. It contains
one `ObjectCaptureSession`, one `ObjectCaptureView`, camera authorization, and
no production coordinator, repository, reconstruction, `ARView`, additional
`ARSession`, or custom renderer. The launch argument requests one
`startCapturing()` invocation only after the framework reports `ready`.

The app was installed under its separate bundle identifier and launched from
`devicectl` with no Device Hub screen mirroring active. It terminated with
signal 5 immediately after entering `ObjectCaptureSession.startCapturing()`.

Minimal crash report: `ObjectCaptureMinimalRepro-2026-11-15-191212.ips`.

## Matching crash signature

Both production and isolated runs report:

```text
Exception: EXC_BREAKPOINT (SIGTRAP)
Termination: SIGNAL, Trace/BPT trap: 5
Faulting thread: 0, com.apple.main-thread
Program counter: 0x000000026f883a98

0 specialized static DataModel.makeDeviceMotionEstimatorDesc(captureMode:) + 260
1 DataModel.startCapturing() + 440
2 ObjectCaptureSession.startCapturing() + 576
```

The next frame is the respective application call site:

```text
Production: ObjectCaptureCoordinator.startFreeformCapture()
Isolated:   ReproCoordinator.startFreeform()
```

The public iOS 27 SDK exposes `startCapturing()` and no separate public
freeform capture-mode configuration. Both callers verify that the active
session is `ready` before invoking it.

## Expected result

`startCapturing()` should transition the ready session to `capturing`, or
report a documented recoverable framework error. It must not execute a
framework breakpoint that terminates the process.

## Actual result and assessment

`_RealityKit_SwiftUI` traps while constructing its internal device-motion
estimator descriptor. The same signature occurs outside the production app and
without screen mirroring. This is evidence of an iOS 27.3 beta RealityKit
framework defect. No undocumented workaround, assertion suppression, or Metal
validation change has been introduced.

No photographs, depth maps, capture datasets, or other private user content
are required to reproduce or attach to the feedback report.
