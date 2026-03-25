import UIKit
import Vision

struct DetectedCardCandidate: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
}

enum CardDetectionService {
    static func detectCards(in image: UIImage) async -> [DetectedCardCandidate] {
        guard let normalizedImage = image.normalized(),
              let cgImage = normalizedImage.cgImage else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let observations = (request.results as? [VNRectangleObservation]) ?? []
                let cropped = observations
                    .sorted { area(of: $0.boundingBox) > area(of: $1.boundingBox) }
                    .prefix(4)
                    .compactMap { cropImage(normalizedImage, cgImage: cgImage, observation: $0) }
                    .map { DetectedCardCandidate(image: $0) }

                continuation.resume(returning: cropped)
            }

            request.minimumAspectRatio = 0.45
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.15
            request.maximumObservations = 4
            request.minimumConfidence = 0.5
            request.quadratureTolerance = 20

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private static func cropImage(_ image: UIImage, cgImage: CGImage, observation: VNRectangleObservation) -> UIImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let box = observation.boundingBox

        let rawRect = CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        )

        let paddedRect = rawRect
            .insetBy(dx: -12, dy: -12)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cropped = cgImage.cropping(to: paddedRect.integral) else {
            return nil
        }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }
}

private extension UIImage {
    func normalized() -> UIImage? {
        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}
