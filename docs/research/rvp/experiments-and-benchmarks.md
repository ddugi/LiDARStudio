# Experiments and benchmarks

These experiments are isolated research proposals. They do not authorize production-code changes or third-party dependency adoption. Each run uses one camera session and retains no private imagery outside its approved local dataset.

## Common measurement protocol

Record for every run:

- app build, git revision, Xcode/iOS/device model;
- enabled ARKit configuration and capability results;
- duration, frame/color/depth counts, missing-depth and dropped-work counts;
- tracking-state timeline and session errors/interruptions;
- CPU/GPU time where measurable, peak memory, storage growth, thermal state;
- algorithm configuration, source hashes, wall time, cancellation behavior;
- trajectory metrics (ATE/RPE where reference exists) and geometry metrics (accuracy, completeness, Chamfer-L1, F-score) where ground truth exists.

Use the same capture for competing offline methods. Never compare methods using different user motion and call it an algorithm comparison.

## Experiment 1 — RGB-D frame and pose recording

**Question:** Can public ARKit APIs deliver a coherent, bounded, reproducible RGB-depth-pose dataset without destabilizing the app?

**Method:** On one supported physical iPhone, record `capturedImage`, raw `sceneDepth`, confidence, intrinsics, camera transform, timestamp, tracking state, and dimensional transforms for 30, 60, and 180 seconds. Use a static textured room and a slow loop. No scene reconstruction, Object Capture, or RoomPlan in the same run.

**Acceptance criteria:**

- 30-second run has increasing real AR frame and depth counts.
- UI Start/Stop remains responsive and dataset closes cleanly.
- Three Start/Stop cycles succeed with no second camera session.
- Manifest/frame count/checksums agree after relaunch.
- Queue is bounded; retained frame objects do not grow with duration.
- Missing depth and dropped processing are recorded, never synthesized.
- No crash, watchdog, jetsam, critical thermal state, or unexpected session recreation.

**Stop conditions:** Any UI freeze, camera conflict, persistent tracking failure, corrupt manifest, unbounded memory trend, critical thermal state, or private/undocumented API requirement.

## Experiment 2 — Camera-pose validation

**Question:** Are ARKit poses internally consistent enough for fusion, and can a geometry-only check detect weak segments?

**Method:** Convert confidence-filtered depth to decimated point clouds. For adjacent/key frames, run a deterministic point-to-plane registration initialized by ARKit relative pose. Report residuals, overlap, correction magnitude, information-matrix eigenvalues, and degeneracy. Do not overwrite ARKit poses.

**Acceptance criteria:**

- Synthetic transforms recover within predeclared tolerances.
- Static repeated captures produce bounded residual/correction distributions.
- Deliberately low-structure scenes are flagged as weak/degenerate rather than “accurate.”
- The validator processes offline and reproduces identical results from the same manifest/configuration.
- A bad correction is rejected by objective gates and preserves baseline pose.

**Stop conditions:** Depth/color geometry cannot be reproduced, optimizer diverges on golden data, results depend on frame arrival order, or degeneracy is not distinguishable from success.

## Experiment 3 — Baseline reconstruction comparison

**Question:** What quality and cost do Apple and a simple independent baseline achieve before advanced RVP-inspired methods?

**Method:** For the same small room/object-scale ARKit dataset, compare: (A) ARKit scene mesh when supported, (B) fixed-resolution confidence-weighted TSDF using ARKit poses, and (C) the same TSDF after only accepted pose corrections. Use a measured static test scene or a repeatable reference mesh where permitted.

**Acceptance criteria:**

- All outputs are traceable to the same frame set and coordinate frame.
- Valid mesh files reopen; empty/corrupt outputs fail validation.
- Report accuracy, completeness, Chamfer-L1, F-score at declared thresholds, triangle count, holes/components, runtime, peak memory, and thermal state.
- A claimed improvement must exceed run-to-run variance on at least three captures.

**Stop conditions:** No trustworthy reference/alignment, baseline cannot complete within bounded resources, or method comparison changes input data/resolution without disclosure.

## Experiment 4 — Offline pose refinement

**Question:** Does direct/geometric optimization improve completed iPhone captures over the ARKit trajectory?

**Method:** On Mac, start with a small keyframe window. Compare geometry-only ICP/local-map refinement, direct depth/intensity alignment, and then bounded BA. Keep input calibration and baseline trajectory immutable. Evaluate both trajectory and reconstruction; better residual alone is not sufficient.

**Acceptance criteria:**

- Optimizer converges on synthetic/golden cases and reports covariance/conditioning.
- On real captures, reconstruction metrics improve beyond repeatability without increasing catastrophic failures.
- Refined trajectory remains aligned to the baseline world and can be reverted instantly.
- Cancellation preserves dataset and partial diagnostics.
- Runtime and peak memory are documented for Apple silicon.

**Stop conditions:** Metric regression, systematic scale drift, high sensitivity to initialization, false convergence, reliance on private data, or no statistically meaningful benefit over ARKit.

## Experiment 5 — Adaptive TSDF proof of concept

**Question:** Can variance-adaptive voxel allocation reduce memory while preserving a fixed-resolution TSDF’s geometry on Apple GPU?

**Method:** First implement and freeze a fixed-resolution reference. In a standalone Mac Metal harness, add a flat hashed two-resolution voxel representation inspired by the published MrHash concept without copying source. Replay recorded depth/pose frames; only after correctness on Mac consider an iPhone run.

**Acceptance criteria:**

- Golden scenes match the reference TSDF/mesh within declared numerical tolerance.
- At matched geometry quality, peak voxel memory improves by a predeclared target (initial target: ≥30%).
- Hash occupancy, collision/probe counts, allocation failures, and coarse/fine voxel counts are observable.
- Deterministic replay produces stable metrics.
- iPhone test, if reached, remains responsive and handles serious/critical thermal state safely.

**Stop conditions:** License ambiguity requires source copying, hash allocation is unbounded, correctness differs nondeterministically, quality loss exceeds tolerance, or the fixed baseline already violates device resource limits.

## Deferred experiment — Gaussian Splatting

**Decision:** **No-go until Experiments 1–4 pass and Experiment 5 has a bounded result.**

Only then test a Mac-only, geometry-first Gaussian representation against TSDF/mesh. Required measures include map accuracy/completeness, number of primitives, memory, training time, render frame time, and failure on motion-distorted/dynamic sequences. Do not market it as higher detail without a controlled textured-object or scene study.

## Dataset ladder

1. **Synthetic unit data:** known intrinsics, poses, planes/cubes; no privacy risk.
2. **Small controlled iPhone capture:** static textured tabletop/room, 30 seconds.
3. **Repeated capture set:** same path/scene three times for variance.
4. **Public RGB-D benchmark:** validates general math but not iPhone domain fit.
5. **VBR subset:** stresses external-LiDAR algorithms only; it is not an iPhone acceptance dataset.

## Benchmark report template

```text
Experiment/run ID:
Question and preregistered thresholds:
Input dataset hash and license:
Device/OS/build:
Method and version:
Configuration:
Frames accepted/dropped/missing depth:
Tracking and thermal events:
Runtime / peak memory / storage:
Trajectory metrics:
Geometry metrics:
Failure evidence:
Result: PASS / FAIL / INCONCLUSIVE / NOT RUN
Product claim authorized: none unless separately approved
```

## Recommended single-object acceptance test

Use one rigid, matte, richly textured object with measured dimensions and distinct fine markings. Capture a repeatable slow loop at fixed lighting. Compare Object Capture USDZ only as Apple’s photogrammetry baseline; compare ARKit RGB-D methods separately because their inputs and intended outputs differ. Blind-review texture legibility and measure geometry against a reference, while recording compute and failures. A visually pleasing viewer screenshot alone is not acceptance evidence.
