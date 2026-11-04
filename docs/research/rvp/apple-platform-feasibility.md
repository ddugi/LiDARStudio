# Apple platform feasibility

This assessment concerns public APIs only. Status labels are defined in [publication-index.md](publication-index.md).

## Public data boundary

| Capability | Public Apple surface | Assessment |
|---|---|---|
| World pose | `ARFrame.camera.transform`, tracking state, timestamp | **[Verified]** Available from an active `ARSession`; Apple describes world tracking as visual-inertial odometry. |
| RGB image | `ARFrame.capturedImage` and camera intrinsics | **[Verified]** Available for an AR session, subject to camera permission and session lifecycle. |
| Rear scene depth | `ARFrame.sceneDepth.depthMap` and optional `confidenceMap` | **[Verified]** Available when `supportsFrameSemantics(.sceneDepth)` is true and the semantic is enabled. Apple says it is sampled using the LiDAR scanner and aligned to the current frame. |
| Smoothed depth | `ARFrame.smoothedSceneDepth` | **[Verified]** Useful for display; temporal smoothing can hide per-frame measurement behavior and should not replace raw `sceneDepth` in a baseline recorder without an explicit experiment. |
| Scene mesh | `ARWorldTrackingConfiguration.sceneReconstruction` and `ARMeshAnchor` | **[Verified]** Available only after `supportsSceneReconstruction(.mesh)` succeeds. This is an ARKit estimate, not raw LiDAR returns. |
| Object Capture photos/progress | `ObjectCaptureSession`, `ObjectCaptureView`, feedback, tracking, shot count, captured image directory | **[Verified]** Publicly supported capture state and photo workflow. Reconstruction is a separate `PhotogrammetrySession` phase. |
| Object Capture raw LiDAR/depth | No documented `ObjectCaptureSession` property for raw depth or LiDAR samples | **[Inferred]** Treat as unavailable. Do not introspect private framework state or claim LiDAR use from Object Capture alone. |
| Room semantics | RoomPlan `RoomCaptureSession`/`CapturedRoom` and USD export | **[Verified]** Apple states RoomPlan uses camera feed, LiDAR readings, ML, and RealityKit to produce parametric room components. It does not expose raw LiDAR measurements as a RoomPlan output contract. |
| Factory sensor extrinsics | No reviewed public API for modifying internal LiDAR↔RGB calibration | **[Unknown/No public contract found]** Ca²Lib is not a basis for changing Apple factory calibration. |

## Framework-by-framework assessment

### ARKit

**[Verified] Native fit: high for recording and baseline geometry.** ARKit exposes the minimal research tuple needed for an RGB-D experiment: color buffer, scene depth in meters, confidence, intrinsics, timestamp, camera pose, tracking state, and optional mesh anchors. Capability checks are mandatory.

**[Inferred] Limitations:** Apple controls sensor fusion, denoising, calibration, resolution, and pose estimation. The API does not promise raw time-of-flight returns, per-ray emission timing, or spinning-LiDAR-style intensity. Algorithms must be reformulated for dense, lower-resolution phone depth rather than assuming Ouster range images.

### RealityKit and Object Capture

**[Verified] Native fit: high for supported photogrammetry; low as a research RGB-D source.** `ObjectCaptureSession` manages guided image capture and exposes real state/feedback/shot counts. `PhotogrammetrySession` turns an image directory into a model on supported hardware.

**[Inferred] Architecture rule:** Object Studio remains an isolated Apple-owned pipeline. It must never run concurrently with the experimental ARKit recorder. RVP-derived refinement should consume a separately and explicitly recorded dataset.

### RoomPlan

**[Verified] Native fit: high for parametric rooms.** It outputs semantic room elements and USD representations.

**[Inferred] Research fit: limited.** Use its output as a product baseline or coarse structural reference. Do not reinterpret RoomPlan output as raw depth evidence or feed it into a method that expects per-frame LiDAR scans without a documented conversion.

### Swift, Accelerate, and Metal

**[Verified]** Swift can own lifecycle, storage, experiment orchestration, and safe typed data. Metal provides general GPU compute; Metal Performance Shaders supplies Apple-tuned primitives.

**[Inferred]** Suitable original-development components:

- Swift/Accelerate: timestamp validation, pose math, downsampling, normal estimation, small-window ICP, metrics, file formats.
- Metal compute: depth back-projection, normal maps, TSDF integration, hash-table operations, raycasting, mesh cell classification.
- Mac Apple silicon: batch nonlinear optimization, larger voxel volumes, experiments, and reconstruction comparison.

**[Verified]** CUDA source does not run on Apple GPUs. Replacing syntax is insufficient: CUDA-specific scheduling, memory, atomics, third-party kernels, and numerical behavior need a new Metal implementation and tests.

## Compute and product placement

| Method | iPhone live | iPhone deferred | Mac offline | Rationale |
|---|---:|---:|---:|---|
| Frame/pose recording | **[Inferred] Go** | — | Import | Public ARKit data; prioritize bounded buffers and disk streaming. |
| Pose validation metrics | **[Inferred] Go** | Go | Go | Low/moderate compute if decimated. |
| Small-window point-to-plane ICP | **[Inferred] Experiment** | Go | Go | Needs confidence/degeneracy validation and strict frame budget. |
| Direct multi-cue alignment | **[Inferred] No-go initially** | Experiment | Go | Sensitive and compute-heavy; establish data quality first. |
| Full-session BA | **[Inferred] No-go live** | No-go initially | Experiment | Sparse solver memory and nonlinear iterations are poor live-iPhone fit. |
| Fixed-resolution TSDF | **[Inferred] Experiment** | Go | Go | Baseline required before adaptive hashing. |
| Adaptive hashed TSDF | **[Inferred] No-go initially** | Experiment | Experiment | Original Metal work and memory-budget validation needed. |
| Gaussian Splatting training | **[Inferred] No-go** | No-go initially | Research experiment | CUDA reference, high implementation/compute risk, no product evidence yet. |
| Gaussian viewer | **[Inferred] Later experiment** | Go if bounded | Go | Rendering is separable from training but needs an agreed asset format. |

## Memory and thermal constraints

**[Verified]** iOS memory is shared and device-dependent; exceeding the limit can terminate the process. Apple recommends measuring peak/suspended memory and responding quickly to pressure. `ProcessInfo.thermalState` reports nominal/fair/serious/critical, and Apple recommends reducing or stopping camera and other intensive work at critical state.

**[Inferred] Engineering limits for experiments:**

- Stream frames to an app-owned draft; do not retain unbounded `ARFrame`, `CVPixelBuffer`, or mesh-anchor histories.
- Bound queue depth and drop work—not source evidence—when processing falls behind; record the drop.
- Separate capture and processing phases when possible.
- Set explicit budgets per device experiment rather than assuming a universal RAM ceiling.
- Record thermal-state transitions, peak resident memory, wall time, GPU time where available, and interruptions.
- Stop safely on critical thermal state or memory pressure and preserve the dataset manifest.

## What native Apple APIs can implement now

1. **[Verified]** Capability-gated RGB-D/pose recording with timestamps, confidence, tracking state, and optional ARKit mesh snapshots.
2. **[Verified]** Supported Object Capture photogrammetry and RoomPlan workflows, kept isolated.
3. **[Inferred]** Reproducible dataset manifests, pose export, confidence-filtered point clouds, baseline trajectory and geometry metrics.
4. **[Inferred]** A fixed-resolution TSDF reference and small-window ICP using original Swift/Metal/Accelerate code.

## What requires original development

1. **[Inferred]** Multi-cue direct registration and bundle adjustment adapted to ARKit frame geometry.
2. **[Inferred]** Generalized uncertainty models calibrated for iPhone scene depth.
3. **[Inferred]** Variance-adaptive voxel hashing and mesh extraction in Metal.
4. **[Inferred]** Any Gaussian optimization/rasterization pipeline on Apple GPU.
5. **[Inferred]** Mac/iPhone dataset and job interchange, provenance, resumability, and quantitative comparison tooling.

## Primary Apple references

- [ARKit scene depth](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth)
- [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)
- [ARWorldTrackingConfiguration](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration)
- [Scene reconstruction](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction)
- [Managing AR session lifecycle](https://developer.apple.com/documentation/arkit/managing-session-life-cycle-and-tracking-quality)
- [ObjectCaptureSession](https://developer.apple.com/documentation/realitykit/objectcapturesession)
- [PhotogrammetrySession](https://developer.apple.com/documentation/realitykit/photogrammetrysession)
- [RoomPlan](https://developer.apple.com/documentation/roomplan)
- [Metal](https://developer.apple.com/documentation/metal)
- [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders)
- [Reducing memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use)
- [ProcessInfo thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
