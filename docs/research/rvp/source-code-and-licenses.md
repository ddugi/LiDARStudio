# Source code and license register

This is an engineering inventory, not legal advice. No dependency has been added to LiDARStudio. Recheck the exact revision and every transitive dependency before any adoption.

## Register

| Work | Official artifact | Observed license | Important dependencies/constraints | Product decision |
|---|---|---|---|---|
| Photometric BA | [`rvp-group/ba-mdslam`](https://github.com/rvp-group/ba-mdslam) | **[Verified] BSD-3-Clause** at repository level | CUDA, C++, ROS data, SRRG components; repository says refactored code may not reproduce paper exactly | **[Inferred] Reference only.** Clean-room Apple implementation; audit transitive licenses before reuse. |
| MrHash | [`rvp-group/mrhash`](https://github.com/rvp-group/mrhash) | **[Verified] Mixed notices:** GPL-3 and Gaussian-Splatting license files are present; top-level scope is not sufficiently clear | CUDA/GPU pipeline, Python packaging, submodules, GS components | **No-go for source integration** until file-level provenance and commercial compatibility are established in writing. Ideas/paper may inform original research. |
| MAD-BA | [`rvp-group/mad-ba`](https://github.com/rvp-group/mad-ba) | **[Unknown]** No top-level license declaration found in reviewed tree | Ubuntu 20.04, ROS Noetic, Docker, solver modules | **No-go for copying or distribution.** Contact maintainers or wait for explicit license. |
| MAD-ICP | [`rvp-group/mad-icp`](https://github.com/rvp-group/mad-icp) | **[Verified] BSD-3-Clause** | Eigen 3.3, OpenMP, pybind11, optional YAML/Python; Linux CI | Candidate for algorithm comparison. Any shipping integration still needs notices, dependency SBOM, Apple portability and performance review. |
| MD-SLAM | [`rvp-group/mdslam`](https://github.com/rvp-group/mdslam) | **[Verified] BSD-3-Clause** at repository level | ROS Noetic, Eigen, SuiteSparse, PCL, Qt/OpenGL, SRRG core/solver/HBST | **[Inferred] Reference architecture only.** Transitive stack is large and non-iOS. |
| Splat-LOAM | [`rvp-group/Splat-LOAM`](https://github.com/rvp-group/Splat-LOAM) | **[Verified] BSD-3-Clause** reported by repository | NVIDIA CUDA strictly required by official implementation; Python/native GS/rasterization dependencies | **No-go for iOS source integration.** A Metal version would be original development; audit any format/viewer code independently. |
| Ca²Lib | [`rvp-group/ca2lib`](https://github.com/rvp-group/ca2lib) | **[Verified] BSD-3-Clause** | Docker/ROS/SRRG and calibration libraries | Research reference; not needed for Apple internal sensor calibration. |
| VBR devkit | [`rvp-group/vbr-devkit`](https://github.com/rvp-group/vbr-devkit) | **[Verified] BSD-3-Clause** | Python, ROS1 bags, conversion packages | Allow only in an isolated research environment after dependency lock/audit. Not an app dependency. |
| VBR dataset | [RVP dataset page](https://rvp-group.net/slam-dataset.html) | **[Verified] CC BY-SA 4.0** stated on dataset page | Large RGB/LiDAR/IMU dataset; derived/distributed artifacts may trigger share-alike obligations | Download only for approved experiments; retain attribution and keep dataset outside app/repository. Legal review before redistributing derivatives. |
| Unified thesis | [Sapienza IRIS](https://hdl.handle.net/11573/1709138) | **[Verified] All rights reserved** on repository record | 64 MB thesis; reading/citation permitted by access, copying/reuse not granted | Cite and summarize; do not copy figures, tables, or text into product material beyond copyright-safe quotation. |

## License rules for this research program

1. **[Verified repository policy]** LiDARStudio remains proprietary; no third-party source enters the production tree until license, attribution, patent, and transitive obligations are recorded.
2. **[Inferred]** “Public on GitHub,” “open access,” and “open source” are three different claims. Only an explicit license grants reusable source rights.
3. **[Inferred]** A permissive top-level license does not automatically resolve submodules, datasets, model weights, papers, or bundled rasterizers.
4. **[Inferred]** GPL or custom research-only code must not be mixed into the proprietary app without owner-approved legal review and a distribution plan.
5. **[Inferred]** Prefer paper-derived clean-room implementations for core IP: record the paper equations, independent design, tests, authorship, and absence of copied code.

## Required dependency review record

Before approving a repository, capture:

- exact URL, tag and commit hash;
- license file and copyright holders;
- file-level exceptions and generated code;
- submodules and package lockfiles;
- runtime, build-only, dataset, model, and test dependencies;
- notice/source-disclosure obligations;
- patents or explicit patent clauses;
- supported Apple platforms/architectures;
- security/maintenance status;
- owner approval and intended use (research tool, Mac helper, or shipped app).

## Current conclusion

**[Inferred]** None of the RVP implementations should be added to the iPhone target now. MAD-ICP is the cleanest future comparison candidate; VBR tooling belongs in an isolated benchmark environment; the remaining methods are best treated as algorithmic references until portability and license gaps close.
