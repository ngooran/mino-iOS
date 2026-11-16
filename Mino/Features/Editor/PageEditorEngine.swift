//
//  PageEditorEngine.swift
//  Mino
//
//  Finishes what the page editor saved with PDFKit: optionally flattens
//  annotations and form fields with MuPDF, so a signature can't be moved
//  and a filled form can't be changed.
//

import Foundation

nonisolated enum PageEditorEngine {

    /// Copies `source` (a PDF written by PDFKit) to `outputURL`.
    /// - Parameters:
    ///   - flattenAnnotations: Make annotations part of the page. Links stay links.
    ///   - flattenForm: Make form fields part of the page.
    /// - Returns: The page count.
    @discardableResult
    static func finish(source: URL, flattenAnnotations: Bool, flattenForm: Bool, outputURL: URL) throws -> Int {
        MuPDF.prepareOutput(outputURL)
        guard flattenAnnotations || flattenForm else {
            try FileManager.default.copyItem(at: source, to: outputURL)
            return try MuPDF.withPDF(at: outputURL) { ctx, doc, _ in Int(mino_count_pages(ctx, doc)) }
        }
        return try MuPDF.withPDF(at: source) { ctx, doc, pdf in
            guard mino_bake(ctx, pdf, flattenAnnotations ? 1 : 0, flattenForm ? 1 : 0) == 0 else {
                throw MuPDFError.unknownError(MuPDF.lastError())
            }
            // Content streams are written as they are. Letting MuPDF clean them
            // after baking produced pages that PDFKit could not read (IRS W-9).
            guard mino_save_pdf_untouched(ctx, pdf, outputURL.path, 2) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
            return Int(mino_count_pages(ctx, doc))
        }
    }
}
