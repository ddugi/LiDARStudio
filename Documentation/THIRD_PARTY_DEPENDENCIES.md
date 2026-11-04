# Third-Party Dependency Register

Last reviewed: 2026-11-04

LiDARStudio currently includes **no third-party software packages, copied source
code, or binary dependencies**. Research publications are cited for study only;
their source code has not been incorporated into the application.

The application uses Apple platform SDKs supplied with Xcode:

| Framework | Purpose | Distribution |
| --- | --- | --- |
| SwiftUI | Application interface and navigation | Apple platform SDK |
| Foundation | Models, dates, JSON, and local file storage | Apple platform SDK |
| AVFoundation | Camera availability and permission status | Apple platform SDK |
| ARKit | World tracking, LiDAR diagnostics, scene depth, and mesh capability checks | Apple platform SDK |
| RealityKit | Object Capture session, photogrammetry, and model presentation | Apple platform SDK |
| RoomPlan | Room-capture capability checks and future isolated room workflow | Apple platform SDK |
| QuickLook | Local USDZ presentation | Apple platform SDK |
| UIKit, CoreImage, ImageIO | Platform integration and local image encoding | Apple platform SDK |
| OSLog | Privacy-aware local diagnostics | Apple platform SDK |
| UniformTypeIdentifiers | Local file-type handling | Apple platform SDK |
| Swift Testing | Automated test framework | Apple platform SDK/Xcode |

Apple SDK frameworks are governed by the applicable Apple developer agreements
and operating-system terms. Update this register before adding any package,
binary framework, source dependency, font, icon set, or other external asset.

## Project-owned artwork

The `AppIcon` artwork was supplied and approved by Dugi Selmanaj for
LiDARStudio. It is project-owned proprietary material and is not licensed for
reuse merely because the repository is publicly visible. See the root LICENSE
and `Documentation/AppIconRequirements.md`.
