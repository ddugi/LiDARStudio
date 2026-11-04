# RVP research decision register

Decisions apply to the research roadmap as of 2026-11-03. Revisit them when evidence changes. “Go” authorizes an isolated experiment, not a production capability.

| ID | Decision | Status | Evidence and rationale | Revisit trigger |
|---|---|---|---|---|
| RVP-001 | Preserve Apple capture engines as isolated product paths. | **GO** | **[Verified]** Object Capture, RoomPlan, and ARKit have different public session contracts; project policy permits only one camera owner. | Apple publishes a supported shared-session design or product architecture changes. |
| RVP-002 | Build a public-API RGB-D/pose recorder before reconstruction research. | **GO — experiment** | **[Verified]** ARKit exposes scene depth, confidence, image, intrinsics, timestamp, pose, and tracking state on capable devices. | Experiment 1 fails its responsiveness/data-integrity gates. |
| RVP-003 | Claim Object Capture exposes raw LiDAR data. | **NO-GO** | **[Inferred from public API surface]** Object Capture documents capture state/photos; no raw depth/LiDAR stream is exposed. | New official Apple documentation/API. |
| RVP-004 | Use ARKit pose as baseline and store refinements separately. | **GO** | **[Verified]** ARKit provides VIO pose; RVP refinement methods require initialization. Separate artifacts preserve evidence and reversibility. | Never remove baseline; schema may evolve. |
| RVP-005 | Prototype confidence-aware geometric pose validation. | **GO — after recorder** | **[Inferred]** MAD-ICP’s uncertainty-aware local-map ideas are valuable, but iPhone noise/geometry must be calibrated independently. | Experiment 2 cannot detect degeneracy or shows no diagnostic value. |
| RVP-006 | Port RVP CUDA repositories directly to iOS. | **NO-GO** | **[Verified]** CUDA implementations require NVIDIA; Apple GPU compute uses Metal. Several stacks also require ROS/Linux. | None; only a new Apple implementation or supported upstream Metal port changes this. |
| RVP-007 | Add MAD-ICP as a production dependency now. | **NO-GO for product; conditional for isolated benchmark** | **[Verified]** BSD-3-Clause is favorable, but transitive review, Apple build, performance, and domain validation are incomplete. | Completed SBOM/license review plus Experiments 1–3. |
| RVP-008 | Copy or integrate MAD-BA source. | **NO-GO** | **[Unknown]** No explicit repository license was established. Public availability is not permission. | Maintainer adds an acceptable explicit license and dependencies pass review. |
| RVP-009 | Copy or integrate MrHash source. | **NO-GO** | **[Verified]** Repository contains GPL-3 and custom Gaussian-Splatting notices with unresolved file-level scope. | Written licensing/provenance review compatible with proprietary distribution. |
| RVP-010 | Implement a fixed-resolution TSDF baseline. | **GO — after pose/data validation** | **[Verified]** TSDF is the necessary control for evaluating adaptive allocation; ARKit depth/poses can provide inputs. | Experiment 1/2 failure or fixed baseline exceeds safe resource limits. |
| RVP-011 | Implement variance-adaptive hashing in Metal. | **CONDITIONAL GO — Mac proof of concept** | **[Inferred]** MrHash reports a strong memory-quality idea, but published hardware and CUDA implementation do not establish Apple feasibility. | Experiment 5 meets correctness/memory thresholds; license-clean independent design documented. |
| RVP-012 | Run full bundle adjustment live on iPhone. | **NO-GO initially** | **[Inferred]** Sparse nonlinear optimization has high memory/thermal risk and no demonstrated product benefit on iPhone data. | Mac offline experiment shows material benefit and profiling supports a bounded mobile window. |
| RVP-013 | Develop Gaussian Splatting now. | **NO-GO / deferred** | **[Verified]** Splat-LOAM is CUDA-only and sensitive to motion distortion; **[Inferred]** capture, pose, and TSDF baselines have higher information value. | Experiments 1–5 pass, licensing is clear, and a product acceptance metric is approved. |
| RVP-014 | Use Ca²Lib to recalibrate the internal Apple sensor rig. | **NO-GO** | **[Verified]** Ca²Lib targets accessible external LiDAR/RGB rigs; no public Apple API for changing factory extrinsics was found. | Apple publishes supported calibration access. |
| RVP-015 | Use VBR as proof of iPhone performance. | **NO-GO** | **[Verified]** VBR uses external Ouster/stereo/RTK-IMU hardware and different sampling. It is a robustness benchmark, not phone-domain validation. | Never as sole proof; pair with representative iPhone datasets. |
| RVP-016 | Keep datasets local and immutable by default. | **GO** | **[Verified project policy]** Local-first storage and IP/privacy requirements; **[Inferred]** immutable evidence enables reproducibility and safe recovery. | Explicit product-owner approval for a transfer workflow. |

## Recommended implementation order

1. RGB-D frame/pose recording and data-contract tests.
2. Camera-pose and depth-registration validation.
3. Fixed-resolution TSDF and Apple baseline comparison.
4. Uncertainty-aware local registration.
5. Mac offline direct/geometric refinement and bounded BA.
6. Clean-room adaptive Metal TSDF proof of concept.
7. Reassess Gaussian mapping only with measured unmet product need.

## Five-method executive conclusion

| Priority | Method | Value | Complexity | Compute placement | Decision |
|---:|---|---|---|---|---|
| 1 | Calibration/synchronization discipline (Ca²Lib/VBR) | Prevents invalid multimodal conclusions | Medium | iPhone capture + offline validation | **GO** |
| 2 | Uncertainty-aware ICP/local mapping (MAD-ICP) | Detects/corrects local pose drift and degeneracy | High | Decimated iPhone or Mac | **GO, experiment** |
| 3 | Sensor-neutral direct alignment (MD-SLAM) | Reuses one architecture across RGB-D/range | High | Mac first | **CONDITIONAL** |
| 4 | Photometric/geometric BA | Global trajectory/map refinement | Very high | Mac offline | **CONDITIONAL** |
| 5 | Variance-adaptive TSDF hashing (MrHash concept) | Better detail per memory budget | Very high | Mac Metal, then iPhone | **CONDITIONAL** |

## Evidence gaps blocking product commitments

- iPhone RGB-depth alignment and timestamp repeatability across real sessions;
- scene-depth noise/uncertainty by distance, material, lighting, and confidence class;
- pose-refinement benefit against measured geometry, not only optimizer residual;
- sustained memory, GPU, energy, and thermal behavior on target devices;
- clean license/SBOM for any reused implementation;
- user-visible quality benefit compared with Apple Object Capture, RoomPlan, and ARKit mesh baselines.

Until these gaps close, all advanced methods remain research proposals rather than LiDARStudio capabilities.
