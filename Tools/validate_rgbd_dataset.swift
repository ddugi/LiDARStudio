#!/usr/bin/env swift

import Foundation
import ImageIO

struct Resolution: Decodable { let width: Int; let height: Int }
struct Counts: Decodable {
    let framesWritten: Int
    let rgbFramesWritten: Int
    let depthFramesWritten: Int
}
struct Manifest: Decodable {
    let schemaVersion: Int
    let status: String
    let counts: Counts
    let frameMetadataFiles: [String]
}
struct ColorFile: Decodable { let filename: String; let resolution: Resolution }
struct DepthFile: Decodable {
    let filename: String
    let resolution: Resolution
    let storedBytesPerRow: Int
}
struct ConfidenceFile: Decodable {
    let filename: String
    let resolution: Resolution
    let storedBytesPerRow: Int
}
struct Frame: Decodable {
    let sequence: Int
    let timestamp: Double
    let cameraIntrinsics: [Float]
    let cameraTransform: [Float]
    let color: ColorFile
    let depth: DepthFile
    let confidence: ConfidenceFile?
}

func contained(_ candidate: URL, in root: URL) -> Bool {
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
    let candidatePath = candidate.standardizedFileURL.resolvingSymlinksInPath().path
    return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
}

func size(_ url: URL) -> Int? {
    try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift Tools/validate_rgbd_dataset.swift /path/to/RGBD-dataset\n", stderr)
    exit(64)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
var errors: [String] = []
var warnings: [String] = []

do {
    let manifest = try decoder.decode(
        Manifest.self,
        from: Data(contentsOf: root.appendingPathComponent("manifest.json"))
    )
    if manifest.schemaVersion != 1 { errors.append("Unsupported schema version \(manifest.schemaVersion).") }
    if manifest.status != "completed" { warnings.append("Dataset status is \(manifest.status).") }
    if manifest.counts.framesWritten != manifest.frameMetadataFiles.count {
        errors.append("Manifest count does not match metadata list.")
    }

    var previousTimestamp: Double?
    var checked = 0
    for relativePath in manifest.frameMetadataFiles {
        let metadataURL = root.appendingPathComponent(relativePath)
        guard contained(metadataURL, in: root) else {
            errors.append("Unsafe metadata path: \(relativePath)")
            continue
        }
        let frame = try decoder.decode(Frame.self, from: Data(contentsOf: metadataURL))
        checked += 1
        if !frame.timestamp.isFinite || frame.timestamp < 0 {
            errors.append("Frame \(frame.sequence): invalid timestamp.")
        }
        if let previousTimestamp, frame.timestamp <= previousTimestamp {
            errors.append("Frame \(frame.sequence): timestamp is not strictly increasing.")
        }
        previousTimestamp = frame.timestamp
        if frame.cameraIntrinsics.count != 9 || !frame.cameraIntrinsics.allSatisfy(\.isFinite) || frame.cameraIntrinsics[0] <= 0 || frame.cameraIntrinsics[4] <= 0 {
            errors.append("Frame \(frame.sequence): invalid intrinsics.")
        }
        if frame.cameraTransform.count != 16 || !frame.cameraTransform.allSatisfy(\.isFinite) {
            errors.append("Frame \(frame.sequence): invalid pose.")
        } else {
            let t = frame.cameraTransform
            if abs(t[3]) > 0.001 || abs(t[7]) > 0.001 || abs(t[11]) > 0.001 || abs(t[15] - 1) > 0.001 {
                errors.append("Frame \(frame.sequence): pose is not homogeneous.")
            }
        }

        let colorURL = root.appendingPathComponent(frame.color.filename)
        if !contained(colorURL, in: root) || CGImageSourceCreateWithURL(colorURL as CFURL, nil) == nil {
            errors.append("Frame \(frame.sequence): RGB image cannot be opened.")
        }
        let depthURL = root.appendingPathComponent(frame.depth.filename)
        let expectedDepth = frame.depth.resolution.width * frame.depth.resolution.height * 4
        if !contained(depthURL, in: root) || size(depthURL) != expectedDepth || frame.depth.storedBytesPerRow != frame.depth.resolution.width * 4 {
            errors.append("Frame \(frame.sequence): depth file layout is invalid.")
        }
        if let confidence = frame.confidence {
            let confidenceURL = root.appendingPathComponent(confidence.filename)
            let expected = confidence.resolution.width * confidence.resolution.height
            if !contained(confidenceURL, in: root) || size(confidenceURL) != expected || confidence.storedBytesPerRow != confidence.resolution.width {
                errors.append("Frame \(frame.sequence): confidence file layout is invalid.")
            }
        } else {
            warnings.append("Frame \(frame.sequence): no confidence map.")
        }
    }
    if checked == 0 { errors.append("No readable frame metadata.") }
    if manifest.counts.rgbFramesWritten != checked || manifest.counts.depthFramesWritten != checked {
        errors.append("RGB/depth counts do not match checked frame count.")
    }

    print("Dataset: \(root.path)")
    print("Frames checked: \(checked)")
    warnings.forEach { print("WARNING: \($0)") }
    errors.forEach { print("ERROR: \($0)") }
    print(errors.isEmpty ? "VALID" : "INVALID")
    exit(errors.isEmpty ? 0 : 1)
} catch {
    fputs("INVALID: \(error.localizedDescription)\n", stderr)
    exit(1)
}
