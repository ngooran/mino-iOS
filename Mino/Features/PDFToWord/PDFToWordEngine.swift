//
//  PDFToWordEngine.swift
//  Mino
//
//  PDF to Text takes the text of a PDF in reading order. Pages that are
//  pictures of text are read with text recognition first.
//
//  `convertToWord` (MuPDF's docx writer) is here but not offered in the app:
//  it did not pass the quality gate (ROADMAP.md, section 11). It stays so the
//  gate can be run again (WordGateTests) when MuPDF's writer improves.
//

import Foundation

nonisolated enum PDFToWordEngine {

    /// Options for MuPDF's docx writer.
    static let wordOptions = ""

    /// Writes an editable Word file. Returns the page count of the source.
    @discardableResult
    static func convertToWord(
        documentURL: URL,
        outputURL: URL,
        readScans: Bool,
        options: String = wordOptions,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> Int {
        // Scanned pages get a text layer first; the writer then finds their text.
        var source = documentURL
        var scratch: URL?
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        if readScans, try hasPagesWithoutText(documentURL) {
            let recognized = try TextRecognizer.recognize(documentURL: documentURL) { progress?($0 * 0.7) }
            let searchable = FileManager.default.temporaryDirectory.appendingPathComponent("word-\(UUID().uuidString).pdf")
            try TextRecognizer.makeSearchablePDF(documentURL: documentURL, pages: recognized, outputURL: searchable)
            source = searchable
            scratch = searchable
        }
        try Task.checkCancellation()

        return try MuPDF.withContext { ctx in
            guard let doc = mino_open_document(ctx, source.path) else {
                throw MuPDFError.documentOpenFailed(path: source.path, reason: MuPDF.lastError())
            }
            defer { mino_drop_document(ctx, doc) }
            MuPDF.prepareOutput(outputURL)
            guard mino_write_docx(ctx, doc, outputURL.path, options) == 0 else {
                // Not shown in the app (gate only), so not in the String Catalog.
                throw MuPDFError.unknownError("docx writer failed: \(MuPDF.lastError())")
            }
            progress?(1)
            return Int(mino_count_pages(ctx, doc))
        }
    }

    /// The text of the document, pages separated by an empty line.
    static func text(of documentURL: URL, readScans: Bool, progress: (@Sendable (Double) -> Void)? = nil) throws -> String {
        var recognized: [Int: String] = [:]
        if readScans, try hasPagesWithoutText(documentURL) {
            for page in try TextRecognizer.recognize(documentURL: documentURL, progress: { progress?($0 * 0.9) }) where page.existingText == nil {
                recognized[page.index] = page.text
            }
        }
        return try MuPDF.withContext { ctx in
            guard let doc = mino_open_document(ctx, documentURL.path) else {
                throw MuPDFError.documentOpenFailed(path: documentURL.path, reason: MuPDF.lastError())
            }
            defer { mino_drop_document(ctx, doc) }
            var pages: [String] = []
            for index in 0..<Int(mino_count_pages(ctx, doc)) {
                try Task.checkCancellation()
                if let text = recognized[index] {
                    pages.append(text)
                } else {
                    pages.append(pageText(ctx, doc, index: index))
                }
            }
            progress?(1)
            return pages
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
    }

    private static func pageText(_ ctx: UnsafeMutablePointer<fz_context>, _ doc: UnsafeMutablePointer<fz_document>, index: Int) -> String {
        guard let pointer = mino_copy_page_text(ctx, doc, Int32(index)) else { return "" }
        defer { mino_free_text(ctx, pointer) }
        return String(cString: pointer)
    }

    /// True when at least one page has (almost) no text: a scan.
    static func hasPagesWithoutText(_ documentURL: URL) throws -> Bool {
        try MuPDF.withContext { ctx in
            guard let doc = mino_open_document(ctx, documentURL.path) else {
                throw MuPDFError.documentOpenFailed(path: documentURL.path, reason: MuPDF.lastError())
            }
            defer { mino_drop_document(ctx, doc) }
            for index in 0..<Int(mino_count_pages(ctx, doc)) {
                let letters = pageText(ctx, doc, index: index).unicodeScalars.filter(CharacterSet.alphanumerics.contains).count
                if letters < TextRecognizer.existingTextThreshold { return true }
            }
            return false
        }
    }
}
