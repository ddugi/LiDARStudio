# RealityKit Object Capture Metal Validation Assertion

Proprietary diagnostic material. Copyright © 2026 Dugi Selmanaj. All rights reserved.

## Environment

- Xcode 27.0 (27A266a)
- iOS 27.2 (24B119)
- iPhone 18 Pro (`iPhone19,2`, arm64e.x1)
- Metal API Validation enabled
- Production application bundle: `se.dugiselmanaj.lidarstudio2`
- Production source revision: `1d3d2d78dcce1e395dc3e80f915667bf6cbcac7a`

## Production reproduction

1. Start one `ObjectCaptureSession` and display Apple's `ObjectCaptureView`.
2. Wait until the framework reports `ready` and camera tracking reports `normal`.
3. Invoke `startDetecting()` once.
4. Observe that it returns `true` and the framework transitions to `detecting`.
5. Stop at the first Metal validation assertion.

The captured log sequence immediately before the assertion was:

```text
UI_RETRY_TAPPED
Invoking object detection requestID=2 reason=user retry frameworkState=ready tracking=normal cameraAuthorization=AVAuthorizationStatus(rawValue: 3)
Object detection requestID=2 returned true; frameworkState=ready
Object Capture state changed to detecting
ObjectCaptureSession.runMaskingManager(_:): Skipped bounding box detection because plane is not available!
ObjectCaptureSession.integratePointCloud(_:): Failed to run voxel integration pipeline in scene mode!
validateComputeFunctionArguments, line 1094: error 'Compute Function(meshShadowCalculateMip): missing Threadgroup Memory binding at index 0 for perPixelData[0].'
```

## First failing thread

```text
0  __pthread_kill
1  pthread_kill
2  abort
3  __assert_rtn
4  MTLReportFailure.cold.1
5  MTLReportFailure
6  -[MTLDebugComputeCommandEncoder validateComputeFunctionArgumentsCommon]
7  -[MTLDebugComputeCommandEncoder dispatchThreadgroups:threadsPerThreadgroup:]
8  -[CaptureMTLComputeCommandEncoder dispatchThreadgroups:threadsPerThreadgroup:]
9  re::MeshShadowGenerateMipmapNode::execute
10 re::RenderGraphExecutable::execute
11 re::RenderFrame::execute
12 re::DrawingManager::executeFrameInternal
13 RealityKit render-thread closure
14 re::runInLocalAutoreleasePool
15 re::RenderThread::threadFuncStatic
16 std thread proxy
17 _pthread_start
```

At the stop, the main thread was in `re::RenderThread::waitForFramePacing`, reached from `re::RenderThread::commitFrame`, `re::DrawingManager::commitFrameInternal`, and `RealityKit.ARView.commonRenderCallback`.

Xcode reported approximately 111% CPU, 1,007.8 MB memory, 928 KB/s disk activity, and 59 FPS at the assertion. The debugger paused the process at the abort assertion; stopping the debug session then terminated it with code 9. No new watchdog or jetsam report was produced for that debugger-intercepted run.

## Framework binaries

- RealityKit UUID: `D3308A06-F34F-3708-B26D-D93F834F8023`
- MetalTools UUID: `F16B3AFC-1AE4-3601-AFC3-48645292789A`

Xcode resolved the internal RealityKit C++ function names shown above. Apple source file and line symbols were not available locally.

## Isolated reproduction target

The sibling Xcode project contains one `ObjectCaptureSession`, Apple's `ObjectCaptureView`, camera authorization, and manual Detect, Freeform, and Cancel controls. It intentionally excludes custom rendering, `ARView`, additional `ARSession` instances, reconstruction, persistence, and the production state machine. The session is placed in the SwiftUI hierarchy before `start(imagesDirectory:)` runs from `ObjectCaptureView.onAppear`.

The isolated app was automatically signed by the configured Personal Team, installed on the same physical iPhone under the separate bundle identifier `se.dugiselmanaj.lidarstudio2.objectcapture-repro`, and run under LLDB with Metal API Validation enabled. The production process was terminated before the controlled repro so that only the isolated app owned the camera session.

The isolated app reached `ready`, camera tracking became `normal`, and the first detection request returned the recoverable result `false` with `noObjectFoundAtDetectionPoint`. A subsequent user detection request returned `true`, transitioned the framework to `detecting`, and reproduced the same Metal assertion:

```text
REPRO_CREATE_SESSION
REPRO_VIEW_APPEARED
REPRO_SESSION_START
REPRO_SESSION_START_RETURNED
REPRO_STATE ready
REPRO_TRACKING limited(reason: initializing)
REPRO_TRACKING normal
REPRO_DETECT_BEGIN tracking=normal
Got error calling startDetecting! error=noObjectFoundAtDetectionPoint
REPRO_DETECT_RETURNED started=false state=ready
REPRO_DETECT_BEGIN tracking=normal
REPRO_DETECT_RETURNED started=true state=ready
REPRO_STATE detecting
ObjectCaptureSession.runMaskingManager(_:): Skipped bounding box detection because plane is not available!
ObjectCaptureSession.integratePointCloud(_:): Failed to run voxel integration pipeline in scene mode!
validateComputeFunctionArguments, line 1094: error 'Compute Function(meshShadowCalculateMip): missing Threadgroup Memory binding at index 0 for perPixelData[0].'
```

The isolated first failing thread was:

```text
0  __pthread_kill
1  pthread_kill
2  abort
3  __assert_rtn
4  MTLReportFailure.cold.1
5  MTLReportFailure
6  -[MTLDebugComputeCommandEncoder validateComputeFunctionArgumentsCommon]
7  -[MTLDebugComputeCommandEncoder dispatchThreadgroups:threadsPerThreadgroup:]
8  re::MeshShadowGenerateMipmapNode::execute
9  re::RenderGraphExecutable::execute
10 re::RenderFrame::execute
11 re::DrawingManager::executeFrameInternal
12 RealityKit render-thread closure
13 re::runInLocalAutoreleasePool
14 re::RenderThread::threadFuncStatic
15 std thread proxy
16 _pthread_start
```

The isolated main thread was waiting in `re::RenderThread::waitForFramePacing`, followed by `re::RenderThread::commitFrame`, `re::DrawingManager::commitFrameInternal`, and `RealityKit.ARView.commonRenderCallback`, matching the production stop. This establishes a framework-level reproduction without the production coordinator, persistence, reconstruction, custom overlays, or production session/view mounting order.

## Expected result

Object detection should either begin, report a recoverable lack of a supporting plane, or return a documented framework failure without a Metal validation assertion or process abort.

## Actual result

After `startDetecting()` returns `true` and state becomes `detecting`, RealityKit's mesh-shadow mip generation dispatches a compute function without the required threadgroup-memory binding. Metal validation aborts on RealityKit's render thread.
