//
//  PencilTextExtractor.swift
//  Prototype
//
//  Apple PencilKit & Vision OCR Handwriting Extraction Layer
//  Converts PKDrawing handwriting strokes directly into text using on-device VNRecognizeTextRequest.
//
//  The sketch canvas draws in white on a clear background, which Vision cannot read (it expects dark ink on a
//  light page), so the strokes are re-inked in black and drawn on white, with a margin, before recognition.
//

import PencilKit
import UIKit
import Vision

@MainActor
public enum PencilTextExtractor {

    /// Extracts handwritten text from an Apple Pencil PKCanvasView drawing using Apple Vision OCR.
    public static func extractText(from canvasView: PKCanvasView) async -> String {
        await extractText(from: canvasView.drawing)
    }

    /// Extracts handwritten text from a PKDrawing instance. Returns "" when there is nothing legible.
    public static func extractText(from drawing: PKDrawing) async -> String {
        guard let page = renderForRecognition(drawing) else { return "" }
        return await Task.detached(priority: .userInitiated) { recognise(page) }.value
    }

    /// The drawing as dark ink on a white page with a margin, large enough for the recogniser to read.
    private static func renderForRecognition(_ drawing: PKDrawing) -> CGImage? {
        let bounds = drawing.bounds
        guard !bounds.isEmpty, bounds.width > 4, bounds.height > 4 else { return nil }

        let dark = PKDrawing(strokes: drawing.strokes.map { stroke in
            var recoloured = stroke
            recoloured.ink = PKInk(stroke.ink.inkType, color: .black)
            return recoloured
        })

        let margin = max(40, min(bounds.width, bounds.height) * 0.25)
        let rect = dark.bounds.insetBy(dx: -margin, dy: -margin)
        // About 2000 px on the long side, never less than 2x
        let scale = max(2, min(4, 2000 / max(rect.width, rect.height)))
        // PencilKit inverts ink for dark mode (black would be drawn white), so draw it under a light appearance
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = dark.image(from: rect, scale: scale)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let page = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        return page.cgImage
    }

    nonisolated private static func recognise(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "en-IN"]
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return "" }

        // Top line first, left to right within a line
        let observations = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.04
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
