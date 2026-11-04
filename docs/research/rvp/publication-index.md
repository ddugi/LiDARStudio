# RVP publication index

Research snapshot: 2026-11-03
Product owner and intended IP owner: Dugi Selmanaj
Copyright © 2026 Dugi Selmanaj. All rights reserved.

This inventory separates published research from LiDARStudio product claims. Nothing below asserts that a method is implemented or validated in LiDARStudio.

## Technical report summary

**Research result.** The RVP body of work is most valuable as a coherent sequence: disciplined calibration/synchronization → modality-neutral direct registration → uncertainty-aware local odometry → global pose/structure refinement → memory-aware reconstruction. It does not provide a drop-in iPhone stack.

**Five highest-value methods:** calibration/synchronization discipline (Ca²Lib/VBR), uncertainty-aware point-cloud registration (MAD-ICP), sensor-neutral direct alignment (MD-SLAM), offline photometric/geometric bundle adjustment, and variance-adaptive TSDF hashing (MrHash). See [algorithms-and-methods.md](algorithms-and-methods.md) for dependencies.

| Question | Evidence-based answer |
|---|---|
| What can native Apple APIs provide? | **[Verified]** ARKit RGB image, intrinsics, timestamp, pose/tracking, LiDAR-derived scene depth/confidence, and optional scene mesh; RealityKit supported photo capture/photogrammetry; RoomPlan parametric rooms/USD. |
| What requires original development? | **[Inferred]** Direct registration, iPhone-specific uncertainty, BA, adaptive TSDF/mesh pipeline, and any Metal Gaussian optimizer. CUDA/ROS implementations are not Apple-native. |
| Expected complexity? | **[Inferred]** Medium for recording/validation, high for ICP/fixed TSDF, very high for direct BA/adaptive hashing/Gaussian optimization. |
| Compute placement? | **[Inferred]** Capture and bounded validation on iPhone; initial BA, adaptive reconstruction, and Gaussian research on Apple-silicon Mac. |
| Main evidence gaps? | **[Unknown]** iPhone depth noise/timing, measurable refinement benefit, sustained memory/thermal behavior, and several file-level/transitive licenses. |
| Recommended order? | Recorder → pose validation → fixed TSDF baseline → uncertainty-aware ICP → Mac pose refinement → adaptive Metal TSDF → reconsider Gaussian mapping. |
| Go/no-go? | **Go** for isolated recording, validation and baseline experiments. **Conditional** for Mac refinement/adaptive TSDF. **No-go now** for source integration, live full BA, or Gaussian product claims. |

Detailed Apple boundaries are in [apple-platform-feasibility.md](apple-platform-feasibility.md), experimental gates in [experiments-and-benchmarks.md](experiments-and-benchmarks.md), and formal decisions in [decision-register.md](decision-register.md).

## Evidence legend

- **[Verified]** Directly supported by a paper, publisher record, official project page, official repository, or Apple documentation.
- **[Inferred]** Engineering assessment derived from verified facts; it still requires an experiment.
- **[Unknown]** The reviewed primary sources do not establish the point.

## 1. Photometric LiDAR and RGB-D Bundle Adjustment

- **[Verified] Authors/year:** Luca Di Giammarino, Emanuele Giacomini, Leonardo Brizi, Omar Salem, Giorgio Grisetti; 2023.
- **[Verified] Original source:** IEEE Robotics and Automation Letters 8(7), 4362–4369. DOI [10.1109/LRA.2023.3281907](https://doi.org/10.1109/LRA.2023.3281907); [open preprint](https://arxiv.org/abs/2303.16878).
- **[Verified] Problem:** Globally refine sensor trajectory and 3D structure for either RGB-D or spinning LiDAR without explicit feature correspondences.
- **[Verified] Mathematical method:** Range/depth and intensity are represented as multi-channel images. A projection model maps a 3D map point into each sensor image; robust photometric residuals across observing poses form a nonlinear least-squares bundle-adjustment problem over poses and structure.
- **[Verified] Inputs/outputs:** Synchronized grayscale/intensity and depth/range images, calibration, and an initial pose/map estimate → refined poses and 3D map.
- **[Verified] Hardware dependencies:** The released implementation is CUDA/C++ and its data path expects ROS-style synchronized image topics. It is not a native Apple GPU implementation.
- **[Verified] Open source/license/dependencies:** [`rvp-group/ba-mdslam`](https://github.com/rvp-group/ba-mdslam), BSD-3-Clause at repository level; CUDA plus the SRRG/solver ecosystem and Linux/ROS tooling require a transitive license audit.
- **[Verified] Published evaluation:** The paper reports results on public RGB-D and LiDAR benchmarks, on par with or better than compared sensor-specific SLAM/BA methods, and reports benefit from joint RGB-D/LiDAR use. The repository warns that refactoring means current code is not expected to reproduce exact paper numbers.
- **[Verified] Known limitations:** Needs an adequate initialization, calibrated projection, synchronized modalities, and photometric consistency; direct optimization remains vulnerable to local minima and appearance changes.
- **[Inferred] LiDARStudio use:** Strong offline pose-refinement reference after an ARKit recording. A fresh Swift/Metal implementation is more appropriate than embedding the CUDA/ROS stack.

## 2. MrHash — Resolution Where It Counts

- **[Verified] Authors/year:** Lorenzo De Rebotti, Emanuele Giacomini, Giorgio Grisetti, Luca Di Giammarino; ACM Transactions on Graphics, 2025/2026 publication cycle.
- **[Verified] Original source:** *Resolution Where It Counts: Hash-based GPU-Accelerated 3D Reconstruction via Variance-Adaptive Voxel Grids*. DOI [10.1145/3777909](https://doi.org/10.1145/3777909); [project page](https://rvp-group.github.io/mrhash/); [preprint](https://arxiv.org/abs/2511.21459).
- **[Verified] Problem:** Real-time TSDF surface reconstruction at large scale without paying fine-voxel memory cost everywhere.
- **[Verified] Mathematical method:** Weighted TSDF fusion in a flat GPU hash table; local TSDF variance selects coarse or fine voxel resolution. The flat representation avoids hierarchical octree traversal and supports raycasting/mesh extraction; optional Gaussian rendering is layered on top.
- **[Verified] Inputs/outputs:** Calibrated depth images or LiDAR point clouds plus poses → TSDF volume, rendered depth/normal views, and mesh; optional Gaussian representation/rendering.
- **[Verified] Hardware dependencies:** Published experiments used an Intel i9-13900K, 128 GB RAM, and NVIDIA RTX 4090 with 24 GB VRAM. The source is GPU/CUDA-oriented.
- **[Verified] Open source/license/dependencies:** [`rvp-group/mrhash`](https://github.com/rvp-group/mrhash). The repository exposes GPL-3 and a separate Gaussian-Splatting license in `LICENSES`; a single permissive product-use grant was not established.
- **[Verified] Published evaluation:** RGB-D and LiDAR evaluations use accuracy, completeness, Chamfer-L1, F-score, memory, and runtime. The project reports state-of-the-art-range reconstruction accuracy with better efficiency; published tests use ground-truth poses, which isolates mapping from tracking.
- **[Verified] Known limitations:** Accuracy depends on pose quality and voxel/variance thresholds. Published compute is far above an iPhone budget. Mixed licensing blocks adoption until a file-level legal review is complete.
- **[Inferred] LiDARStudio use:** The variance-adaptive allocation idea is highly valuable for an original Metal TSDF prototype; do not port source before licensing and algorithmic clean-room review.

## 3. MAD-BA

- **[Verified] Authors/year:** Krzysztof Ćwian, Luca Di Giammarino, Simone Ferrari, Thomas Ciarfuglia, Giorgio Grisetti, Piotr Skrzypczyński; 2025.
- **[Verified] Original source:** IEEE Robotics and Automation Letters 10(7), 7254–7261. DOI [10.1109/LRA.2025.3573628](https://doi.org/10.1109/LRA.2025.3573628); [preprint](https://arxiv.org/abs/2501.03972).
- **[Verified] Problem:** Jointly refine LiDAR poses and map structure instead of optimizing trajectory while holding the map fixed.
- **[Verified] Mathematical method:** A surfel map and pose graph are optimized together. Residual weighting uses a generalized LiDAR measurement-uncertainty model so unreliable range observations contribute less.
- **[Verified] Inputs/outputs:** LiDAR point clouds, initial trajectory, sensor parameters/uncertainty → optimized trajectory and surfel positions/normals.
- **[Verified] Hardware dependencies:** Official repository was developed/tested on Ubuntu 20.04 with ROS Noetic and Docker; no Apple-native implementation is documented.
- **[Verified] Open source:** [`rvp-group/mad-ba`](https://github.com/rvp-group/mad-ba).
- **[Unknown] Code license:** No top-level license file or repository license declaration was visible in the reviewed repository. “Open source” in a paper is not sufficient permission to copy or ship code.
- **[Verified] Published evaluation:** Public-dataset experiments report improvement over most comparable methods; the paper separately evaluates trajectory and structure refinement.
- **[Verified] Known limitations:** Batch/global optimization is initialization- and correspondence-dependent and computationally heavier than odometry. The sensor noise model needs validation for phone scene-depth data.
- **[Inferred] LiDARStudio use:** A later Mac-side refinement stage could jointly correct ARKit poses and a surfel/point representation. No-go for direct source integration until licensing is explicit.

## 4. MAD-ICP

- **[Verified] Authors/year:** Simone Ferrari, Luca Di Giammarino, Leonardo Brizi, Giorgio Grisetti; 2024.
- **[Verified] Original source:** IEEE Robotics and Automation Letters. DOI [10.1109/LRA.2024.3456509](https://doi.org/10.1109/LRA.2024.3456509); [preprint](https://arxiv.org/abs/2405.05828).
- **[Verified] Problem:** Robust LiDAR odometry across different sensors, motion patterns, and environments with one parameterization.
- **[Verified] Mathematical method:** A PCA-based kd-tree compresses local neighborhoods into planar leaves. ICP minimizes leaf-level point-to-plane residuals; the estimated pose uncertainty controls keyframe/local-map growth. It supports an anytime runtime/accuracy tradeoff.
- **[Verified] Inputs/outputs:** Sequential 3D LiDAR scans and calibration/extrinsics → relative poses, trajectory, local map, and pose uncertainty.
- **[Verified] Hardware dependencies:** CPU C++ with OpenMP; released experiments suggest 16 cores/keyframes when available. No CUDA requirement.
- **[Verified] Open source/license/dependencies:** [`rvp-group/mad-icp`](https://github.com/rvp-group/mad-icp), BSD-3-Clause; Eigen 3.3, OpenMP, pybind11, optional YAML/Python runners.
- **[Verified] Published evaluation:** Extensive public datasets cover urban, highway, vegetation, handheld, vehicle, and drone motion. The paper reports comparable-or-better accuracy and no sequence failures in its comparison; the same parameter set was used per LiDAR model.
- **[Verified] Known limitations:** Geometry-only ICP requires enough overlapping structure and a usable initial transform; point-to-plane conditioning deteriorates in geometrically degenerate scenes. Spinning-LiDAR assumptions and density differ from iPhone scene depth.
- **[Inferred] LiDARStudio use:** Best near-term reference for uncertainty-aware frame-to-local-map validation, implemented independently in Swift/C++ or Accelerate on downsampled ARKit depth points.

## 5. MD-SLAM

- **[Verified] Authors/year:** Luca Di Giammarino, Leonardo Brizi, Tiziano Guadagnino, Cyrill Stachniss, Giorgio Grisetti; 2022.
- **[Verified] Original source:** IROS 2022, 11047–11054. DOI [10.1109/IROS47612.2022.9981147](https://doi.org/10.1109/IROS47612.2022.9981147); [preprint](https://arxiv.org/abs/2203.13237).
- **[Verified] Problem:** One direct SLAM design for RGB-D and LiDAR rather than modality-specific pipelines.
- **[Verified] Mathematical method:** Multi-resolution image pyramids carry intensity/range/normal cues. Direct frame registration estimates pose; a pose graph and appearance-based relocalization detect loops, which are geometrically validated with the same registration method.
- **[Verified] Inputs/outputs:** Calibrated, synchronized intensity/grayscale and depth/range images → trajectory, keyframes/graph, and registered point map.
- **[Verified] Hardware dependencies:** Official build targets Ubuntu 20.04, ROS Noetic, PCL, Eigen, SuiteSparse, Qt/OpenGL, and SRRG libraries.
- **[Verified] Open source/license/dependencies:** [`rvp-group/mdslam`](https://github.com/rvp-group/mdslam), BSD-3-Clause at repository level; transitive SRRG/PCL/SuiteSparse licenses still require review.
- **[Verified] Published evaluation:** Comparative public RGB-D and 3D-LiDAR benchmarks report competitive results against sensor-specific methods with one general architecture.
- **[Verified] Known limitations:** Direct alignment needs overlap, gradients, calibration, and an adequate motion prior; loop detection adds storage/compute. ROS/Linux implementation is not deployable as-is on iOS.
- **[Inferred] LiDARStudio use:** Architectural reference for a modality-neutral `Frame/Pyramid/Projection/Residual` offline engine, not a library dependency.

## 6. Splat-LOAM

- **[Verified] Authors/year:** Emanuele Giacomini, Luca Di Giammarino, Lorenzo De Rebotti, Giorgio Grisetti, Martin R. Oswald; 2025.
- **[Verified] Original source:** ICCV 2025. DOI [10.1109/ICCV51701.2025.02565](https://doi.org/10.1109/ICCV51701.2025.02565); [open paper](https://openaccess.thecvf.com/content/ICCV2025/html/Giacomini_Splat-LOAM_Gaussian_Splatting_LiDAR_Odometry_and_Mapping_ICCV_2025_paper.html); [preprint](https://arxiv.org/abs/2503.17491).
- **[Verified] Problem:** Use one compact Gaussian representation for both LiDAR odometry and mapping.
- **[Verified] Mathematical method:** 2D Gaussian primitives are rasterized on a spherical LiDAR image. Mapping minimizes range, normal, opacity, and scale losses with selective densification/pruning; frame-to-model tracking combines geometric and rendered-image residuals.
- **[Verified] Inputs/outputs:** Sequential spinning-LiDAR range images/point clouds, with optional motion aid in evaluated configurations → trajectory and Gaussian map that can render depth/geometry.
- **[Verified] Hardware dependencies:** Official repository explicitly requires an NVIDIA CUDA GPU.
- **[Verified] Open source/license/dependencies:** [`rvp-group/Splat-LOAM`](https://github.com/rvp-group/Splat-LOAM), repository reports BSD-3-Clause; CUDA rasterization and Python/native dependencies need a full manifest audit.
- **[Verified] Published evaluation:** Supplemental results report 0.59% average tracking RPE for Splat-LOAM on the listed successful sequences; mapping is competitive or best on several accuracy/completeness cells. The paper emphasizes low GPU memory relative to neural baselines, not CPU/mobile operation.
- **[Verified] Known limitations:** Authors report strong sensitivity to spinning-LiDAR motion distortion. It is geometry-focused rather than a textured RGB Gaussian product pipeline, and the CUDA renderer is not portable to Metal without redevelopment.
- **[Inferred] LiDARStudio use:** Research-only, Mac-offline track after pose/depth recording and baseline fusion are reliable. Not an iPhone product dependency for the current roadmap.

## 7. Ca²Lib

- **[Verified] Authors/year:** Emanuele Giacomini, Leonardo Brizi, Luca Di Giammarino, Omar Salem, Patrizio Perugini, Giorgio Grisetti; journal publication 2024 (preprint 2023).
- **[Verified] Original source:** *Sensors* 24(3), 956. DOI [10.3390/s24030956](https://doi.org/10.3390/s24030956); [open article](https://www.mdpi.com/1424-8220/24/3/956); [preprint](https://arxiv.org/abs/2309.07874).
- **[Verified] Problem:** Accurate LiDAR-to-RGB extrinsic calibration using inexpensive A3/A4 planar chessboard targets.
- **[Verified] Mathematical method:** Extract the common planar target in camera and LiDAR frames, form robust cross-modal constraints, and jointly optimize the rigid extrinsic transform over several observations.
- **[Verified] Inputs/outputs:** Camera images, LiDAR scans, camera model/intrinsics, and multiple target poses → rigid LiDAR↔camera transform and calibration diagnostics.
- **[Verified] Hardware dependencies:** Designed for external LiDAR/camera rigs and ROS/Docker, not Apple’s factory-integrated internal sensor stack.
- **[Verified] Open source/license/dependencies:** [`rvp-group/ca2lib`](https://github.com/rvp-group/ca2lib), BSD-3-Clause; ROS/SRRG/OpenCV-style transitive components require review.
- **[Verified] Published evaluation:** In the reported comparison, the method obtains 0.11 cm translation error and 0.25×10⁻² rad rotation error, versus 0.82 cm/0.24×10⁻² rad for a cited baseline, using small commercial targets.
- **[Verified] Known limitations:** Requires visible common target observations and external sensor access; cannot recalibrate Apple’s undisclosed internal LiDAR-camera factory model through public APIs.
- **[Inferred] LiDARStudio use:** Methodological guidance for validating exported RGB-depth alignment, not a user-facing iPhone calibration feature.

## 8. VBR — A Vision Benchmark in Rome

- **[Verified] Authors/year:** Leonardo Brizi, Emanuele Giacomini, Luca Di Giammarino, Simone Ferrari, Omar Salem, Lorenzo De Rebotti, Giorgio Grisetti; 2024.
- **[Verified] Original source:** ICRA 2024, 15868–15874. DOI [10.1109/ICRA57147.2024.10611395](https://doi.org/10.1109/ICRA57147.2024.10611395); [preprint](https://arxiv.org/abs/2404.11322); [dataset](https://rvp-group.net/slam-dataset.html).
- **[Verified] Problem:** A heterogeneous benchmark for visual/LiDAR odometry and SLAM across indoor, garden, urban, highway, handheld, and vehicle scenarios.
- **[Verified] Mathematical method:** Hardware synchronization and intrinsic/extrinsic calibration; six-degree-of-freedom ground truth refines RTK-GPS/IMU/LiDAR estimates through bundle adjustment.
- **[Verified] Inputs/outputs:** Stereo RGB, Ouster point clouds, IMU and GPS/ground truth → timestamped ROS bags, calibration, train/test trajectories, and benchmark scores.
- **[Verified] Hardware dependencies:** External global-shutter cameras, Ouster OS0/OS1 LiDAR, SBG RTK-GPS/IMU; 10–30 Hz configurations. This differs materially from an iPhone RGB-D stream.
- **[Verified] Open source/license/dependencies:** Dataset page states CC BY-SA 4.0; [`vbr-devkit`](https://github.com/rvp-group/vbr-devkit) is BSD-3-Clause and uses Python/ROS bag conversion tooling.
- **[Verified] Published evaluation:** The contribution is primarily dataset/ground truth and a public evaluation protocol, with multiple long sequences and a benchmark for TUM-format trajectories—not a product reconstruction-quality claim.
- **[Verified] Known limitations:** Very large downloads; robotics sensor geometry and motion distortion differ from iPhone data. Share-alike terms require review before redistributing derived dataset artifacts.
- **[Inferred] LiDARStudio use:** Useful external stress test for Mac-side pose algorithms after a small native iPhone dataset establishes domain fit.

## 9. Unified multimodal 3D reconstructions thesis

- **[Verified] Author/year:** Luca Di Giammarino; doctoral thesis, Sapienza University of Rome, defended 16 January 2024.
- **[Verified] Original source:** [Sapienza IRIS record and full thesis](https://hdl.handle.net/11573/1709138). No DOI is stated on the repository record.
- **[Verified] Problem:** Unify camera, RGB-D, and LiDAR ideas for robust, scalable SLAM and 3D reconstruction.
- **[Verified] Mathematical method:** Synthesizes visual place recognition, multimodal direct alignment, MD-SLAM, photometric bundle adjustment, geometric refinement, calibration/synchronization, and the VBR dataset.
- **[Verified] Inputs/outputs:** Multiple chapters use different sensor combinations; collectively: RGB/intensity, depth/range, poses, IMU/GPS and calibration → trajectory, map, refined reconstruction, and benchmark data.
- **[Verified] Hardware dependencies:** Research spans RGB-D cameras and external 3D LiDAR systems; it does not establish an iPhone implementation.
- **[Verified] Source/license:** The thesis file is open-access to read but the IRIS record marks it “All rights reserved.” Associated implementations have their own repository licenses.
- **[Verified] Published evaluation:** The thesis consolidates peer-reviewed experiments from its component works; it argues that common projection/direct-optimization machinery can be competitive across modalities.
- **[Verified] Known limitations:** A synthesis does not remove calibration, synchronization, initialization, compute, or modality-domain constraints.
- **[Inferred] LiDARStudio use:** Best conceptual architecture source: retain Apple capture as a trusted front end, persist sensor-neutral frames, and perform optional modular offline refinement.

## Evidence gaps to close

1. **[Unknown]** Exact file-level license boundaries and transitive obligations for MrHash, MAD-BA, Splat-LOAM, and the SRRG dependency family.
2. **[Unknown]** Whether the uncertainty models calibrated for spinning LiDAR transfer to ARKit `sceneDepth` noise and confidence.
3. **[Unknown]** Quantitative benefit of any RVP-inspired refinement over ARKit poses on representative iPhone captures.
4. **[Unknown]** Sustained Metal memory, energy, and thermal limits for an adaptive TSDF implementation on the target iPhone.
5. **[Unknown]** Whether RGB-depth timestamp alignment available through public ARKit data is sufficient for direct photometric BA without additional rolling-shutter modeling.
