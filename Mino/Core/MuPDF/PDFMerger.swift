//
//  PDFMerger.swift
//  Mino
//
//  PDF merge engine using MuPDF
//

import Foundation

/// PDF merger using MuPDF's page grafting API
final class PDFMerger: @unchecked Sendable {

    // MARK: - Merge Operation

    /// Merges multiple PDF files into a single output file
    /// - Parameters:
    ///   - sources: Array of source PDF URLs in desired order
    ///   - outputURL: Destination URL for the merged PDF
    ///   - progressHandler: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: MergeResult with output details
    nonisolated func merge(
        sources: [URL],
        outputURL: URL,
        progressHandler: ((Double, String) -> Void)? = nil
    ) throws -> MergeResult {
        let startTime = Date()

        guard sources.count >= 2 else {
            throw MuPDFError.invalidParameters
        }

        // Create context
        guard let ctx = mino_create_context() else {
            throw MuPDFError.contextCreationFailed
        }
        defer { mino_drop_context(ctx) }

        // Create destination document
        guard let dstDoc = mino_create_pdf_document(ctx) else {
            throw MuPDFError.documentCreationFailed
        }
        defer { mino_drop_pdf_document(ctx, dstDoc) }

        var totalPages = 0
        let sourceCount = sources.count

        // Process each source document
        for (index, sourceURL) in sources.enumerated() {
            let fileName = sourceURL.deletingPathExtension().lastPathComponent
            let progress = Double(index) / Double(sourceCount)
            progressHandler?(progress, fileName)

            // Open source document
            guard let srcDoc = mino_open_document(ctx, sourceURL.path) else {
                let errorMsg = getLastError() ?? "Unknown error"
                throw MuPDFError.documentOpenFailed(path: sourceURL.path, reason: errorMsg)
            }
            defer { mino_drop_document(ctx, srcDoc) }

            // Get PDF-specific handle
            guard let srcPdf = mino_pdf_specifics(ctx, srcDoc) else {
                throw MuPDFError.invalidPDFDocument
            }

            // Get page count
            let pageCount = Int(mino_count_pages(ctx, srcDoc))
            guard pageCount > 0 else { continue }

            // Create a new graft map for THIS source document
            // (graft map tracks source->dest object mappings, so needs to be per-source)
            guard let graftMap = mino_new_graft_map(ctx, dstDoc) else {
                throw MuPDFError.graftMapFailed
            }
            defer { mino_drop_graft_map(ctx, graftMap) }

            // Graft all pages from source to destination
            for pageIndex in 0..<pageCount {
                let result = mino_graft_page(ctx, graftMap, -1, srcPdf, Int32(pageIndex))
                if result != 0 {
                    let errorMsg = getLastError() ?? "Unknown error"
                    mino_clear_error()
                    throw MuPDFError.pageGraftFailed(page: pageIndex, reason: errorMsg)
                }
                totalPages += 1
            }
        }

        progressHandler?(0.95, "Saving")

        // Create output directory if needed
        let outputDir = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Remove existing output file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Save the merged document
        let saveResult = mino_save_pdf(ctx, dstDoc, outputURL.path, 3)
        if saveResult != 0 {
            let errorMsg = getLastError() ?? "Unknown error"
            mino_clear_error()
            throw MuPDFError.saveFailed(reason: errorMsg)
        }

        // Get output file size
        let outputSize = mino_get_file_size(outputURL.path)
        if outputSize < 0 {
            throw MuPDFError.saveFailed(reason: "Could not verify output file")
        }

        let duration = Date().timeIntervalSince(startTime)
        progressHandler?(1.0, "Complete")

        return MergeResult(
            id: UUID(),
            outputURL: outputURL,
            sourceCount: sourceCount,
            totalPages: totalPages,
            outputSize: outputSize,
            duration: duration,
            timestamp: Date()
        )
    }

    // MARK: - Helper Methods

    nonisolated private func getLastError() -> String? {
        guard let cError = mino_get_last_error() else { return nil }
        return String(cString: cError)
    }

    // MARK: - Output URL Generation

    /// Generates an output URL for a merged PDF
    static func generateOutputURL(outputName: String) -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Merged", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: documentsDir,
            withIntermediateDirectories: true
        )

        let timestamp = Int(Date().timeIntervalSince1970)
        let safeName = outputName.isEmpty ? "document" : outputName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        return documentsDir
            .appendingPathComponent("Merged_\(safeName)_\(timestamp)")
            .appendingPathExtension("pdf")
    }

    /// Generates a default output name from source documents
    static func suggestedOutputName(from sources: [PDFDocumentInfo]) -> String {
        guard let first = sources.first else { return "merged" }
        if sources.count == 1 {
            return first.name
        }
        return "\(first.name)_merged"
    }
}
