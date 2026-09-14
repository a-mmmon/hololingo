import Foundation
import UIKit
import Vision
import CoreImage
import ImageIO

@available(iOS 17.0, *)
final class ForegroundSegmentation {
    private static let ciContext = CIContext()

    static func removeBackground(
        from imagePath: String,
        centerX: Double? = nil,
        centerY: Double? = nil
    ) async throws -> String {
        let imageURL = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw SegmentationError.imageNotFound
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let requestHandler = VNImageRequestHandler(url: imageURL, options: [:])
        try requestHandler.perform([request])

        guard let observation = request.results?.first else {
            throw SegmentationError.noForegroundFound
        }

        // iOS 17's VNInstanceMaskObservation does not provide
        // instanceAtPoint(_:). Instead, read the instance-mask pixel at the
        // detector's center point and use that instance ID.
        let instances: IndexSet

        if let x = centerX, let y = centerY {
            instances = instancesAtDetectorCenter(
                observation: observation,
                centerX: x,
                centerY: y
            ) ?? observation.allInstances
        } else {
            instances = observation.allInstances
        }

        guard !instances.isEmpty else {
            throw SegmentationError.noForegroundFound
        }

        let maskedPixelBuffer = try observation.generateMaskedImage(
            ofInstances: instances,
            from: requestHandler,
            croppedToInstancesExtent: true
        )

        let maskedCIImage = CIImage(cvPixelBuffer: maskedPixelBuffer)

        guard let cgImage = Self.ciContext.createCGImage(
            maskedCIImage,
            from: maskedCIImage.extent
        ) else {
            throw SegmentationError.imageConversionFailed
        }

        let outputImage = UIImage(
            cgImage: cgImage,
            scale: 1.0,
            orientation: .up
        )

        guard let pngData = outputImage.pngData() else {
            throw SegmentationError.pngCreationFailed
        }

        let outputDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        let filename = "hololingo_cutout_\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let outputURL = outputDirectory.appendingPathComponent(filename)

        try pngData.write(to: outputURL, options: .atomic)

        return outputURL.path
    }

    // MARK: - iOS 17-compatible instance selection

    private static func instancesAtDetectorCenter(
        observation: VNInstanceMaskObservation,
        centerX: Double,
        centerY: Double
    ) -> IndexSet? {
        let mask = observation.instanceMask
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)

        guard width > 0, height > 0 else {
            return nil
        }

        let x = min(max(centerX, 0.0), 1.0)
        let y = min(max(centerY, 0.0), 1.0)

        // Detector coordinates use top-left origin. The mask is a raw pixel
        // buffer, so try both possible vertical interpretations and select the
        // candidate with the strongest local support.
        let topLeftCandidate = sampleInstance(
            mask: mask,
            normalizedX: x,
            normalizedY: y
        )

        let flippedCandidate = sampleInstance(
            mask: mask,
            normalizedX: x,
            normalizedY: 1.0 - y
        )

        switch (topLeftCandidate, flippedCandidate) {
        case let (a?, b?) where a == b:
            return IndexSet(integer: a)
        case let (a?, _):
            return IndexSet(integer: a)
        case let (_, b?):
            return IndexSet(integer: b)
        default:
            return nil
        }
    }

    private static func sampleInstance(
        mask: CVPixelBuffer,
        normalizedX: Double,
        normalizedY: Double
    ) -> Int? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let x = min(max(Int(normalizedX * Double(width - 1)), 0), width - 1)
        let y = min(max(Int(normalizedY * Double(height - 1)), 0), height - 1)

        let format = CVPixelBufferGetPixelFormatType(mask)

        // Vision's legacy VNInstanceMaskObservation exposes an 8-bit instance
        // mask on supported iOS 17 devices. Handle 16-bit too for robustness.
        if format == kCVPixelFormatType_OneComponent8 {
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let value = Int(bytes[y * bytesPerRow + x])
            return value > 0 ? value : nil
        }

        if format == kCVPixelFormatType_OneComponent16 {
            let rowStride = bytesPerRow / MemoryLayout<UInt16>.size
            let values = baseAddress.assumingMemoryBound(to: UInt16.self)
            let value = Int(values[y * rowStride + x])
            return value > 0 ? value : nil
        }

        return nil
    }
}

@available(iOS 17.0, *)
private enum SegmentationError: LocalizedError {
    case imageNotFound
    case noForegroundFound
    case imageConversionFailed
    case pngCreationFailed

    var errorDescription: String? {
        switch self {
        case .imageNotFound:
            return "The captured image could not be found."
        case .noForegroundFound:
            return "Vision could not find a foreground object."
        case .imageConversionFailed:
            return "Could not convert the segmented image."
        case .pngCreationFailed:
            return "Could not create the transparent PNG."
        }
    }
}
