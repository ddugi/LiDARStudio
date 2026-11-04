# Object Capture Minimal Reproduction

Proprietary diagnostic material. Copyright © 2026 Dugi Selmanaj. All rights reserved.

This isolated iPhone application contains one `ObjectCaptureSession`, Apple's `ObjectCaptureView`, camera authorization, manual object detection, freeform capture, and cancellation. It has no LiDARStudio repository, reconstruction pipeline, custom renderer, `ARView`, extra `ARSession`, or production workflow state machine.

The session object is installed in the SwiftUI hierarchy first. `ObjectCaptureSession.start(imagesDirectory:)` is invoked only from `ObjectCaptureView.onAppear`, after camera authorization. Metal API Validation must remain enabled.

Run only one experiment per launch and stop on the first assertion:

1. Create Session and record whether the framework reaches `Ready`.
2. With a visible horizontal supporting plane, tap Detect once.
3. In a separate launch without a supporting plane, tap Detect once.
4. In a separate launch, tap Freeform once from `Ready`.

Relevant unified log markers begin with `REPRO_`.
