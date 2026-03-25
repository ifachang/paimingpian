import UIKit
import Vision

struct OCRTextLine: Equatable {
    let text: String
    let boundingBox: CGRect

    var midY: CGFloat { boundingBox.midY }
    var height: CGFloat { boundingBox.height }
}

enum OCRServiceError: LocalizedError {
    case noTextDetected

    var errorDescription: String? {
        switch self {
        case .noTextDetected:
            return "沒有辨識到文字，請換一張更清楚的名片照片。"
        }
    }
}

enum OCRService {
    static func recognizeCard(from image: UIImage) async throws -> ScannedCard {
        let lines = try await recognizeLines(from: image)
        let card = BusinessCardParser.parse(lines: lines)
        guard card.hasContent else {
            throw OCRServiceError.noTextDetected
        }

        return card
    }

    static func recognizeLines(from image: UIImage) async throws -> [OCRTextLine] {
        guard let cgImage = image.cgImage else {
            throw OCRServiceError.noTextDetected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { observation -> OCRTextLine? in
                        guard let candidate = observation.topCandidates(1).first else {
                            return nil
                        }

                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else {
                            return nil
                        }

                        return OCRTextLine(text: text, boundingBox: observation.boundingBox)
                    }
                    .sorted { lhs, rhs in
                        if abs(lhs.midY - rhs.midY) > 0.02 {
                            return lhs.midY > rhs.midY
                        }

                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    } ?? []

                guard !lines.isEmpty else {
                    continuation.resume(throwing: OCRServiceError.noTextDetected)
                    return
                }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
