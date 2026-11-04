# Algorithms and methods

Status labels are defined in [publication-index.md](publication-index.md). Equations describe research methods, not implemented LiDARStudio features.

## Component dependency map

```text
calibration + timestamps
        │
        ▼
RGB/depth frame + confidence + camera pose
        │
        ├──► depth back-projection ─► point cloud / normals
        │                              │
        │                              ├──► ICP / uncertainty ─► pose correction
        │                              │                         │
        │                              └─────────────────────────┤
        │                                                        ▼
        ├──► image/depth pyramids ─► direct alignment ─► keyframes / pose graph
        │                                                        │
        └────────────────────────────────────────────────────────┤
                                                                 ▼
                                   bundle adjustment / pose refinement
                                                                 │
                                   ┌─────────────────────────────┴──────────┐
                                   ▼                                        ▼
                              TSDF fusion                            Gaussian map
                                   │                                        │
                         adaptive voxel hashing                      differentiable render
                                   │
                              mesh extraction
```

## 1. RGB-D registration

**[Verified]** For a pixel `u`, depth `D(u)`, camera intrinsics `K`, and pose `T`, back-project `p = D(u) K⁻¹ ū`, transform it, then project into the target image. MD-SLAM and the photometric BA paper generalize this through a sensor-specific projection `π` so pinhole RGB-D and spherical LiDAR can share residual machinery.

**[Inferred]** LiDARStudio should normalize recorded data to a neutral frame contract rather than expose ARKit types to every algorithm:

```text
Frame { timestamp, color reference, depth, confidence, intrinsics,
        cameraTransform, image/depth transforms, trackingState }
```

Acceptance depends on explicitly preserving the mapping between depth pixels and the captured image; naïve resizing is not registration.

## 2. Camera pose estimation

**[Verified]** ARKit supplies a six-degree-of-freedom camera transform from visual-inertial odometry. RVP methods treat such a trajectory as either the primary estimate (MD-SLAM/MAD-ICP) or an initialization to refine (photometric BA/MAD-BA).

**[Inferred]** Use ARKit pose as the immutable baseline. Any refined trajectory must be a separate artifact with provenance, algorithm version, residual statistics, and an alignment transform back to the ARKit world frame.

## 3. Direct photometric optimization

For cue `c`, a representative direct residual is:

```text
rᶜᵢⱼ(u) = Iᶜⱼ( π(Tⱼ⁻¹ Tᵢ π⁻¹(u, Dᵢ(u))) ) − Iᶜᵢ(u)
E(T) = Σ ρ( rᵀ W r )
```

**[Verified]** MD-SLAM minimizes pixel-wise differences across intensity/range/normal cue pyramids rather than precomputing sparse feature matches. Coarse-to-fine optimization enlarges the convergence basin; robust loss and validity masks reject bad projections.

**[Inferred]** A phone prototype should begin with depth/geometric residuals and add grayscale only after exposure and depth/color alignment are measured. Direct methods are especially sensitive to rolling shutter, auto-exposure, blur, moving objects, and low gradient.

## 4. Bundle adjustment

**[Verified]** Bundle adjustment jointly minimizes residuals over multiple poses and structure:

```text
(T*, X*) = arg min(T,X) Σ(i,j,k) ρ( ||rᵢⱼk(Tᵢ,Tⱼ,Xk)||²_W )
```

Photometric BA uses rendered/projected multi-cue values without fixed feature association. MAD-BA additionally optimizes surfel structure and applies a generalized LiDAR uncertainty model.

**[Inferred]** Use bounded keyframe windows first. Full-session BA should be a Mac/offline experiment because variable count, memory, and solver factorization scale rapidly.

## 5. Point-cloud registration, ICP, and uncertainty

**[Verified]** A point-to-plane ICP residual is `r = nᵀ(Tp − q)`. MAD-ICP builds planar leaves with PCA, matches reduced structural elements, solves the robust alignment, and derives pose uncertainty from the local optimization information. Uncertainty then governs when to add keyframes to the local map.

**[Inferred]** Confidence-aware downsampling can map ARKit depth confidence into measurement weights, but it must not be called the MAD-ICP uncertainty model until validated. Degeneracy checks should use the information-matrix spectrum and reject corrections when translation or rotation is weakly observable.

## 6. Sensor synchronization

**[Verified]** VBR uses hardware synchronization across external sensors and publishes calibration/timing metadata. ARKit publishes `ARFrame.timestamp`, `capturedImage`, camera pose, and `sceneDepth` generated from LiDAR readings associated with the current frame. Apple notes that different depth systems can have different capture timing; each API’s timestamp semantics must be respected.

**[Inferred]** Store one monotonic timestamp per recorded frame and never pair color/depth solely by arrival order. Record dropped frames, missing depth, and tracking state. Cross-session time bases and an undocumented sensor offset are evidence gaps, not constants to guess.

## 7. TSDF fusion

For signed distance sample `d`, truncation `μ`, weight `w`, and existing voxel `(D,W)`:

```text
d_tsdf = clamp(d / μ, -1, 1)
D' = (W D + w d_tsdf) / (W + w)
W' = min(W + w, Wmax)
```

**[Verified]** TSDF fusion denoises repeated depth observations and provides an implicit zero-level surface. It requires calibrated poses; pose drift becomes duplicated or blurred geometry.

**[Inferred]** First establish a CPU/reference integrator on small volumes, then a Metal compute version. Keep color fusion separate so geometry correctness can be measured independently.

## 8. Adaptive voxel hashing

**[Verified]** MrHash allocates voxel blocks in a flat hash table and selects resolution using local TSDF variance. This concentrates fine resolution near complex geometry while keeping uniform regions coarse.

**[Inferred]** A clean-room Apple design needs: deterministic hash keys, bounded probing, explicit allocation budget, separate coarse/fine pools, eviction policy, and GPU-safe synchronization. Variance thresholds must be learned from iPhone depth noise, not copied from external LiDAR experiments.

## 9. Mesh extraction

**[Verified]** A TSDF mesh is the zero isosurface, commonly extracted with Marching Cubes-style cell classification and interpolation. ARKit can also provide its own scene-reconstruction mesh when supported; that is an Apple-produced estimate, not LiDARStudio’s TSDF output.

**[Inferred]** Run mesh extraction after bounded fusion chunks or offline. Validate manifold defects, component count, triangle density, normal consistency, and metric accuracy before texture work.

## 10. Gaussian Splatting

**[Verified]** Splat-LOAM represents geometry with oriented 2D Gaussian primitives and differentiably rasterizes them on spherical LiDAR images. Its losses constrain depth, normals, opacity, and scale; selective densification and pruning control representation growth.

**[Verified]** The official implementation requires CUDA/NVIDIA. Metal supports general GPU compute, but CUDA kernels and assumptions do not execute on Apple GPUs.

**[Inferred]** A Metal Gaussian pipeline would be original development: data layout, sorting/binning, rasterizer, gradients/optimizer, memory controls, and viewer. It should follow pose refinement and TSDF baselines, not precede them.

## Five most valuable methods for LiDARStudio

1. **[Inferred] Uncertainty-aware local registration (MAD-ICP idea):** best diagnostic for pose drift with moderate compute.
2. **[Inferred] Sensor-neutral direct residuals (MD-SLAM):** a reusable architecture across RGB-D and LiDAR-like depth.
3. **[Inferred] Offline photometric/geometric BA:** strongest route to globally refine a completed capture.
4. **[Inferred] Variance-adaptive TSDF hashing (MrHash idea):** promising memory-quality tradeoff after a fixed-resolution baseline.
5. **[Inferred] Calibration/synchronization discipline (Ca²Lib/VBR):** prerequisite for every multimodal result, even though Apple factory calibration itself is not user-accessible.

Gaussian splatting is strategically interesting but ranks after these five because it has the largest portability, compute, validation, and licensing gap.
