# RGB-D proof-of-concept dataset

Copyright © 2026 Dugi Selmanaj. All rights reserved.

The Environment Studio proof of concept records a bounded, local dataset with one public ARKit `ARSession`. It requests `sceneDepth`; it does not start Object Capture, RoomPlan, mesh reconstruction, or a second camera session.

## Layout

```text
RGBDDatasets/<UUID>/
├── manifest.json
└── frames/
    ├── 000000.json
    ├── 000000.color.jpg
    ├── 000000.depth.f32
    └── 000000.confidence.u8
```

Each frame JSON records the ARKit timestamp, tracking state, camera intrinsics, `T_world_camera` transform, original RGB/depth dimensions, pixel formats, and file names. Depth is stored as packed little-endian `Float32` meters. Confidence is packed one byte per pixel when ARKit supplies it. RGB is preserved at the available camera-buffer resolution as JPEG quality 0.92; the app does not claim lossless color storage.

Sampling is limited to two accepted frames per second, 180 frames, and two pending writes. The manifest counts callbacks, accepted/written frames, queue/rate/depth drops, resolutions, tracking states, and observed sensors. Existing scans are never modified.

## Export and Mac validation

Stop the recording, wait for app validation, then use **Export Dataset**. On the Mac, run:

```sh
swift Tools/validate_rgbd_dataset.swift "/path/to/exported-dataset"
```

The validator checks timestamp ordering, image readability, depth/confidence file sizes, intrinsics, homogeneous camera poses, safe contained paths, and manifest completeness. A valid structural result is not a calibration-accuracy or pose-ground-truth certification.

## Public API limitations

- `sceneDepth` is ARKit's LiDAR-derived, processed scene depth—not raw time-of-flight returns.
- ARKit controls camera exposure, focus, depth filtering, synchronization, and sensor fusion.
- RGB and depth resolutions differ; downstream work must use recorded dimensions and intrinsics.
- ARKit camera poses are visual-inertial estimates and require later evaluation against a baseline.
- The proof of concept records no raw IMU stream and makes no claim that every camera callback has depth.
