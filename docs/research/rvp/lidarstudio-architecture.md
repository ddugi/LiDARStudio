# LiDARStudio research architecture

This is a proposed architecture, not a statement of current product capability. It preserves the existing Object Studio, Room Studio, Environment Studio, local repository, signing, and single-camera-session rule.

## Architectural boundary

```text
                    ┌──────────────── production app ────────────────┐
Object Capture ────►│ Apple-managed photos + Photogrammetry          │
RoomPlan ──────────►│ Apple-managed room capture + parametric output │
ARKit ─────────────►│ capability-gated RGB-D research recorder       │
                    └──────────────────┬─────────────────────────────┘
                                       │ local, explicit dataset
                                       ▼
                    ┌──────────── research processing ───────────────┐
                    │ validation → pose metrics → baseline TSDF      │
                    │ optional ICP/BA → adaptive TSDF experiments    │
                    │ optional Mac jobs; no camera ownership         │
                    └──────────────────┬─────────────────────────────┘
                                       ▼
                    versioned derived artifacts + benchmark report
```

## Design principles

1. **[Verified project constraint] One camera owner.** Object Capture, RoomPlan, and ARKit recording are mutually exclusive state-machine modes.
2. **[Inferred] Capture is evidence, processing is derived.** Original frame files and manifest are immutable; every output names its inputs and algorithm version.
3. **[Inferred] Apple baselines stay intact.** ARKit pose/mesh, RoomPlan result, and Object Capture USDZ are never overwritten by experimental refinements.
4. **[Inferred] Local by default.** Mac transfer or export is explicit and user-initiated. No cloud architecture is assumed.
5. **[Inferred] Failure preserves inputs.** Cancellation or processing failure closes the manifest safely and retains complete frames.

## Proposed modules

### 1. `CaptureArbiter`

Owns a lease for exactly one camera-consuming mode: `.objectCapture`, `.roomPlan`, or `.arkitResearch`. Lease release is idempotent and tied to foreground/background lifecycle.

### 2. `RGBDRecorder`

Receives ARKit delegate callbacks on a dedicated serial queue, copies only required data, writes bounded chunks, and publishes throttled status. It records no frame unless pose, timestamp, intrinsics, and dimensional metadata can be written consistently.

### 3. `ResearchDataset`

Suggested local layout:

```text
dataset-id/
  manifest.json
  frames/
    000000.color.heic
    000000.depth.bin
    000000.confidence.bin
    000000.frame.json
  baselines/
    arkit-trajectory.json
    arkit-mesh.usdz        # only when explicitly exported
  derived/
    <algorithm-id>/<run-id>/manifest.json
  reports/
    benchmark.json
```

The manifest should include API/OS/device versions, capability checks, coordinate conventions, depth units/format, image orientation and transforms, timestamps, dropped-frame reasons, tracking state, thermal events, and checksums. It must not contain hidden/private API data.

### 4. `GeometryCore`

Pure, testable operations: `SE3`, projection/back-projection, confidence filters, voxel sampling, normals, residuals, robust loss, trajectory alignment, and metrics. Keep representations independent of UI and ARKit classes.

### 5. `PoseValidationEngine`

Compares frame overlap, ICP residual, information eigenvalues, relative-pose consistency, and optional ground truth. It may recommend “insufficient evidence”; it must not rewrite pose automatically.

### 6. `FusionEngine`

Start with a deterministic fixed-resolution TSDF reference. A later Metal engine must match a small golden dataset within tolerances before adaptive hashing. Mesh extraction is a separate stage and artifact.

### 7. `OfflineJobRunner`

Runs bounded jobs on device only when appropriate; larger BA/adaptive/GS experiments run on a Mac helper. Job manifests store input hashes, configuration, start/end state, metrics, and failure reason.

## Data contracts

### Frame contract

- monotonic timestamp and sequence number;
- color/depth dimensions, pixel formats, row strides, orientation;
- camera intrinsics and reference resolution;
- depth-to-color/display transform as provided/derived from documented APIs;
- ARKit camera transform and tracking status;
- raw `sceneDepth` and confidence availability flags;
- no retained `ARFrame` object after extraction.

### Derived pose contract

- source trajectory identifier;
- `T_world_camera` convention and units;
- transform aligning refined coordinates to baseline;
- solver, configuration, residual distribution and degeneracy flags;
- rejected frames and reason.

### Geometry contract

- representation (`pointCloud`, `surfel`, `tsdf`, `mesh`, `gaussian`);
- coordinate frame, scale and bounding box;
- source dataset/run hashes;
- accuracy/completeness metrics where ground truth exists;
- renderer/export format does not imply reconstruction validity.

## Recommended implementation order

1. **Go:** recorder and immutable manifest, with no reconstruction.
2. **Go:** pose/data validation and point-cloud export on tiny datasets.
3. **Go:** fixed-resolution CPU TSDF benchmark.
4. **Conditional go:** decimated uncertainty-aware ICP; retain ARKit baseline.
5. **Conditional go:** Mac offline direct/geometric pose refinement.
6. **Conditional go:** Metal fixed TSDF, then adaptive hashing.
7. **No-go for now:** Gaussian training/product claims until baselines, licensing, and compute evidence exist.

## Complexity and compute summary

| Component | Development complexity | Expected compute | Main risk |
|---|---|---|---|
| Recorder/manifest | Medium | I/O and buffer copies | Alignment, retention, storage pressure |
| Pose validator | Medium | CPU, bounded | False confidence in degenerate scenes |
| Fixed TSDF | Medium-high | GPU preferred | Memory grows with volume/resolution |
| ICP | High | CPU/GPU, decimated | Local minima and poor observability |
| Direct alignment | High | GPU/vector CPU | Photometric assumptions and Jacobians |
| Bundle adjustment | Very high | Mac CPU/GPU, sparse solver | Scale, initialization, numerical stability |
| Adaptive hash TSDF | Very high | Metal GPU | Allocation/concurrency/thermal behavior |
| Gaussian optimization | Very high | Mac GPU | CUDA gap, memory, licenses, product value |

## Product-claim firewall

- A recorded depth map is **verified sensor data**, not a high-quality model.
- An increasing frame count is **session activity**, not accurate tracking.
- A completed solver is **processing success**, not geometric accuracy.
- A renderable mesh/splat is **format validity**, not fidelity.
- Only a documented acceptance test can promote an experiment to a product capability.
