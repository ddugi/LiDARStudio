import Foundation
import ImageIO

nonisolated enum RGBDDatasetValidator {
    static func validate(datasetURL: URL) -> RGBDDatasetValidationReport {
        var errors: [String] = []
        var warnings: [String] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestURL = datasetURL.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(RGBDDatasetManifest.self, from: manifestData) else {
            return RGBDDatasetValidationReport(
                datasetURL: datasetURL,
                framesChecked: 0,
                errors: ["manifest.json is missing or invalid."],
                warnings: []
            )
        }

        if manifest.schemaVersion != RGBDDatasetManifest.currentSchemaVersion {
            errors.append("Unsupported manifest schema version \(manifest.schemaVersion).")
        }
        if manifest.status != "completed" {
            warnings.append("Dataset status is \(manifest.status), not completed.")
        }
        if manifest.counts.framesWritten != manifest.frameMetadataFiles.count {
            errors.append("Manifest frame count does not match its metadata file list.")
        }

        var previousTimestamp: TimeInterval?
        var checked = 0
        for relativePath in manifest.frameMetadataFiles {
            let metadataURL = datasetURL.appendingPathComponent(relativePath)
            guard isContained(metadataURL, in: datasetURL) else {
                errors.append("Unsafe metadata path: \(relativePath)")
                continue
            }
            guard let data = try? Data(contentsOf: metadataURL),
                  let frame = try? decoder.decode(RGBDFrameMetadata.self, from: data) else {
                errors.append("Missing or invalid frame metadata: \(relativePath)")
                continue
            }
            checked += 1

            if !frame.timestamp.isFinite || frame.timestamp < 0 {
                errors.append("Frame \(frame.sequence) has an invalid timestamp.")
            }
            if let previousTimestamp, frame.timestamp <= previousTimestamp {
                errors.append("Frame \(frame.sequence) timestamp is not strictly increasing.")
            }
            previousTimestamp = frame.timestamp

            validateMatrices(frame, errors: &errors)
            validateColor(frame.color, sequence: frame.sequence, root: datasetURL, errors: &errors)
            validateDepth(frame.depth, sequence: frame.sequence, root: datasetURL, errors: &errors)
            if let confidence = frame.confidence {
                validateConfidence(confidence, sequence: frame.sequence, root: datasetURL, errors: &errors)
                if confidence.resolution != frame.depth.resolution {
                    errors.append("Frame \(frame.sequence) confidence and depth dimensions differ.")
                }
            } else {
                warnings.append("Frame \(frame.sequence) has no depth confidence map.")
            }
        }

        if checked == 0 { errors.append("Dataset contains no readable frame metadata.") }
        if manifest.counts.rgbFramesWritten != checked || manifest.counts.depthFramesWritten != checked {
            errors.append("RGB/depth counts do not match readable frame metadata.")
        }

        return RGBDDatasetValidationReport(
            datasetURL: datasetURL,
            framesChecked: checked,
            errors: errors,
            warnings: warnings
        )
    }

    private static func validateMatrices(_ frame: RGBDFrameMetadata, errors: inout [String]) {
        guard frame.cameraIntrinsics.count == 9,
              frame.cameraIntrinsics.allSatisfy(\.isFinite),
              frame.cameraIntrinsics[0] > 0,
              frame.cameraIntrinsics[4] > 0 else {
            errors.append("Frame \(frame.sequence) has invalid camera intrinsics.")
            return
        }
        guard frame.cameraTransform.count == 16,
              frame.cameraTransform.allSatisfy(\.isFinite) else {
            errors.append("Frame \(frame.sequence) has an invalid camera transform.")
            return
        }
        let epsilon: Float = 0.001
        if abs(frame.cameraTransform[3]) > epsilon ||
            abs(frame.cameraTransform[7]) > epsilon ||
            abs(frame.cameraTransform[11]) > epsilon ||
            abs(frame.cameraTransform[15] - 1) > epsilon {
            errors.append("Frame \(frame.sequence) camera transform is not a homogeneous pose.")
        }
    }

    private static func validateColor(
        _ color: RGBDColorFile,
        sequence: Int,
        root: URL,
        errors: inout [String]
    ) {
        let url = root.appendingPathComponent(color.filename)
        guard isContained(url, in: root) else {
            errors.append("Frame \(sequence) has an unsafe color path.")
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            errors.append("Frame \(sequence) color image cannot be opened.")
            return
        }
        if width != color.resolution.width || height != color.resolution.height {
            errors.append("Frame \(sequence) color dimensions do not match metadata.")
        }
    }

    private static func validateDepth(
        _ depth: RGBDDepthFile,
        sequence: Int,
        root: URL,
        errors: inout [String]
    ) {
        let url = root.appendingPathComponent(depth.filename)
        let expected = depth.resolution.width * depth.resolution.height * MemoryLayout<Float32>.size
        guard isContained(url, in: root), fileSize(url) == expected else {
            errors.append("Frame \(sequence) depth file is missing or has the wrong size.")
            return
        }
        if depth.storedBytesPerRow != depth.resolution.width * MemoryLayout<Float32>.size {
            errors.append("Frame \(sequence) depth row layout is invalid.")
        }
    }

    private static func validateConfidence(
        _ confidence: RGBDConfidenceFile,
        sequence: Int,
        root: URL,
        errors: inout [String]
    ) {
        let url = root.appendingPathComponent(confidence.filename)
        let expected = confidence.resolution.width * confidence.resolution.height
        guard isContained(url, in: root), fileSize(url) == expected else {
            errors.append("Frame \(sequence) confidence file is missing or has the wrong size.")
            return
        }
        if confidence.storedBytesPerRow != confidence.resolution.width {
            errors.append("Frame \(sequence) confidence row layout is invalid.")
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let candidatePath = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
