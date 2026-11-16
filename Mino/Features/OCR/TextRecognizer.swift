//
//  TextRecognizer.swift
//  Mino
//
//  Recognize Text: Apple Vision reads each page on the device. The text is
//  then laid over the page as an invisible layer, so search, selection and
//  copy work in every PDF app, or it is saved as a text file.
//

import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Vision

/// A word Vision found, in fractions of the page with the origin at the bottom left.
nonisolated struct RecognizedWord: Sendable, Equatable {
    var text: String
    var box: CGRect
}

nonisolated struct RecognizedLine: Sendable, Equatable {
    var text: String
    var box: CGRect
    var words: [RecognizedWord]
}

nonisolated struct RecognizedPage: Sendable {
    /// 0-based page index.
    var index: Int
    /// The page as it is shown, in points.
    var size: CGSize
    var lines: [RecognizedLine]
    /// The page already had text, so it was not read again.
    var existingText: String?

    var text: String {
        existingText ?? lines.map(\.text).joined(separator: "\n")
    }
}

nonisolated enum TextRecognizer {

    /// Resolution pages are read at. 200 dpi is enough for body text and keeps
    /// a page fast.
    static let dpi: CGFloat = 200

    /// Longest side of the image given to Vision, in pixels.
    static let maxPixelSide: CGFloat = 3200

    /// A page with at least this many letters already counts as text.
    static let existingTextThreshold = 12

    // MARK: - Recognition

    /// Reads every page that has no text yet.
    /// - Parameter language: A Vision language code such as "de-DE", or nil to detect it.
    static func recognize(
        documentURL: URL,
        language: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [RecognizedPage] {
        let existing = PDFDocument(url: documentURL)

        return try MuPDF.withContext { ctx in
            guard let doc = mino_open_document(ctx, documentURL.path) else {
                throw MuPDFError.documentOpenFailed(path: documentURL.path, reason: MuPDF.lastError())
            }
            defer { mino_drop_document(ctx, doc) }
            let pageCount = Int(mino_count_pages(ctx, doc))
            var pages: [RecognizedPage] = []

            for index in 0..<pageCount {
                try Task.checkCancellation()
                let size = try MuPDF.pageSize(ctx, doc, index: index)
                var page = RecognizedPage(index: index, size: size, lines: [])

                let text = existing?.page(at: index)?.string ?? ""
                if text.unicodeScalars.filter(CharacterSet.alphanumerics.contains).count >= existingTextThreshold {
                    page.existingText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    var zoom = dpi / 72
                    let longSide = max(size.width, size.height) * zoom
                    if longSide > maxPixelSide { zoom *= maxPixelSide / longSide }
                    // One page at a time: render, read, release.
                    page.lines = try autoreleasepool {
                        try MuPDF.withPageImage(ctx, doc, index: index, zoom: zoom) { image in
                            try recognize(image, language: language)
                        }
                    }
                }
                pages.append(page)
                progress?(Double(index + 1) / Double(pageCount) * 0.9)
            }
            return pages
        }
    }

    /// Reads one image. Lines come back in reading order.
    static func recognize(_ image: CGImage, language: String? = nil) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let language {
            request.recognitionLanguages = [language]
        } else {
            request.automaticallyDetectsLanguage = true
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string
            var words: [RecognizedWord] = []
            // Split at spaces only, so "2026-041" or "don't" stay one word.
            var start: String.Index?
            func close(at end: String.Index) {
                guard let from = start else { return }
                start = nil
                let range = from..<end
                guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { return }
                words.append(RecognizedWord(text: String(string[range]), box: box))
            }
            for index in string.indices {
                if string[index].isWhitespace {
                    close(at: index)
                } else if start == nil {
                    start = index
                }
            }
            close(at: string.endIndex)
            if words.isEmpty {
                words = [RecognizedWord(text: string, box: observation.boundingBox)]
            }
            return RecognizedLine(text: string, box: observation.boundingBox, words: words)
        }
    }

    /// Language codes Vision can read on this device.
    static var supportedLanguages: [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    // MARK: - Output

    /// All text, pages separated by an empty line.
    static func text(of pages: [RecognizedPage]) -> String {
        pages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Saves a copy of the document with the recognized text as an invisible
    /// layer over each page that was read. The page content itself is untouched.
    static func makeSearchablePDF(documentURL: URL, pages: [RecognizedPage], outputURL: URL) throws {
        let recognized = pages.filter { !$0.lines.isEmpty }
        let overlay = FileManager.default.temporaryDirectory.appendingPathComponent("text-layer-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: overlay) }

        if !recognized.isEmpty {
            try writeTextLayer(recognized, to: overlay)
        }

        try MuPDF.withPDF(at: documentURL) { ctx, _, pdf in
            if !recognized.isEmpty {
                let targets = recognized.map { Int32($0.index) }
                guard mino_overlay_pages(ctx, pdf, overlay.path, Int32(targets.count), targets) == 0 else {
                    throw MuPDFError.unknownError(MuPDF.lastError())
                }
            }
            MuPDF.prepareOutput(outputURL)
            guard mino_save_pdf_untouched(ctx, pdf, outputURL.path, 1) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
        }
    }

    /// Draws each page's words as invisible text at the place they were found.
    /// CoreGraphics embeds the fonts it needs, so any script Vision reads can
    /// be searched and copied.
    static func writeTextLayer(_ pages: [RecognizedPage], to url: URL) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw MuPDFError.saveFailed(reason: url.lastPathComponent)
        }
        for page in pages {
            var box = CGRect(origin: .zero, size: page.size)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.setTextDrawingMode(.invisible)
            for line in page.lines {
                for (index, word) in line.words.enumerated() {
                    // A trailing space lets PDF readers tell the words apart.
                    draw(word, appendingSpace: index < line.words.count - 1, in: context, pageSize: page.size)
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func draw(_ word: RecognizedWord, appendingSpace: Bool, in context: CGContext, pageSize: CGSize) {
        let rect = CGRect(
            x: word.box.minX * pageSize.width,
            y: word.box.minY * pageSize.height,
            width: word.box.width * pageSize.width,
            height: word.box.height * pageSize.height
        )
        guard rect.width > 0.5, rect.height > 0.5 else { return }

        // The box spans ascender to descender; the font is a little smaller.
        let fontSize = max(2, rect.height * 0.82)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        guard let measured = CFAttributedStringCreate(nil, word.text as CFString, attributes) else { return }
        let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(measured), nil, nil, nil)
        guard width > 0 else { return }

        let text = appendingSpace ? word.text + " " : word.text
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(string)

        context.saveGState()
        context.textMatrix = .identity
        // Stretch the word to the width Vision measured, so selections line up.
        context.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.2)
        context.scaleBy(x: rect.width / CGFloat(width), y: 1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
