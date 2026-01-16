//
//  PDFSplitter.swift
//  Mino
//
//  PDF split engine using MuPDF
//

import Foundation

/// PDF splitter using MuPDF's page grafting API
final class PDFSplitter: @unchecked Sendable {

    // MARK: - Extract Page Range

    /// Extracts a range of pages from a PDF into a new file
    /// - Parameters:
    ///   - sourceURL: Source PDF URL
    ///   - range: Page range to extract (1-based for user display)
    ///   - outputURL: Destination URL for the extracted pages
    /// - Returns: SplitResult with output details
    nonisolated func extractRange(
        sourceURL: URL,
        range: PageRange,
        outputURL: URL
    ) throws -> SplitResult {
        // Convert from 1-based user display to 0-based internal
        let startPage = range.start - 1
        let endPage = range.end - 1

        // Create context
        guard let ctx = mino_create_context() else {
            throw MuPDFError.contextCreationFailed
        }
        defer { mino_drop_context(ctx) }

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

        // Validate page range
        let pageCount = Int(mino_count_pages(ctx, srcDoc))
        guard startPage >= 0 && endPage < pageCount && startPage <= endPage else {
            throw MuPDFError.invalidPageRange(start: range.start, end: range.end, pageCount: pageCount)
        }

        // Create destination document
        guard let dstDoc = mino_create_pdf_document(ctx) else {
            throw MuPDFError.documentCreationFailed
        }
        defer { mino_drop_pdf_document(ctx, dstDoc) }

        // Create graft map
        guard let graftMap = mino_new_graft_map(ctx, dstDoc) else {
            throw MuPDFError.graftMapFailed
        }
        defer { mino_drop_graft_map(ctx, graftMap) }

        // Graft the specified pages
        for pageIndex in startPage...endPage {
            let result = mino_graft_page(ctx, graftMap, -1, srcPdf, Int32(pageIndex))
            if result != 0 {
                let errorMsg = getLastError() ?? "Unknown error"
                mino_clear_error()
                throw MuPDFError.pageGraftFailed(page: pageIndex, reason: errorMsg)
            }
        }

        // Create output directory if needed
        let outputDir = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Remove existing output file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Save the extracted pages
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

        return SplitResult(
            id: UUID(),
            outputURL: outputURL,
            pageRange: range.displayString,
            pageCount: range.pageCount,
            outputSize: outputSize,
            timestamp: Date()
        )
    }

    // MARK: - Split At Page

    /// Splits a PDF at a specific page into two separate files
    /// - Parameters:
    ///   - sourceURL: Source PDF URL
    ///   - splitPage: Page number where the split occurs (1-based). This page becomes the first page of Part 2.
    ///   - outputURL1: Destination URL for Part 1 (pages 1 to splitPage-1)
    ///   - outputURL2: Destination URL for Part 2 (pages splitPage to end)
    /// - Returns: Array of two SplitResults
    nonisolated func splitAtPage(
        sourceURL: URL,
        splitPage: Int,
        outputURL1: URL,
        outputURL2: URL
    ) throws -> [SplitResult] {
        // Create context
        guard let ctx = mino_create_context() else {
            throw MuPDFError.contextCreationFailed
        }
        defer { mino_drop_context(ctx) }

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

        let pageCount = Int(mino_count_pages(ctx, srcDoc))
        guard pageCount >= 2 else {
            throw MuPDFError.splitFailed(reason: "Document must have at least 2 pages to split")
        }

        // Validate split page (must be between 2 and pageCount)
        guard splitPage >= 2 && splitPage <= pageCount else {
            throw MuPDFError.invalidPageRange(start: splitPage, end: splitPage, pageCount: pageCount)
        }

        var results: [SplitResult] = []

        // Create output directories if needed
        try? FileManager.default.createDirectory(at: outputURL1.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputURL2.deletingLastPathComponent(), withIntermediateDirectories: true)

        // --- Part 1: Pages 1 to splitPage-1 ---
        let part1PageCount = splitPage - 1

        guard let dstDoc1 = mino_create_pdf_document(ctx) else {
            throw MuPDFError.documentCreationFailed
        }

        guard let graftMap1 = mino_new_graft_map(ctx, dstDoc1) else {
            mino_drop_pdf_document(ctx, dstDoc1)
            throw MuPDFError.graftMapFailed
        }

        // Graft pages 0 to splitPage-2 (0-based)
        for pageIndex in 0..<part1PageCount {
            let result = mino_graft_page(ctx, graftMap1, -1, srcPdf, Int32(pageIndex))
            if result != 0 {
                let errorMsg = getLastError() ?? "Unknown error"
                mino_clear_error()
                mino_drop_graft_map(ctx, graftMap1)
                mino_drop_pdf_document(ctx, dstDoc1)
                throw MuPDFError.pageGraftFailed(page: pageIndex, reason: errorMsg)
            }
        }
        mino_drop_graft_map(ctx, graftMap1)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL1)

        // Save Part 1
        let saveResult1 = mino_save_pdf(ctx, dstDoc1, outputURL1.path, 3)
        mino_drop_pdf_document(ctx, dstDoc1)

        if saveResult1 != 0 {
            let errorMsg = getLastError() ?? "Unknown error"
            mino_clear_error()
            throw MuPDFError.saveFailed(reason: errorMsg)
        }

        let outputSize1 = mino_get_file_size(outputURL1.path)
        if outputSize1 < 0 {
            throw MuPDFError.saveFailed(reason: "Could not verify output file for Part 1")
        }

        let result1 = SplitResult(
            id: UUID(),
            outputURL: outputURL1,
            pageRange: part1PageCount == 1 ? "1" : "1-\(part1PageCount)",
            pageCount: part1PageCount,
            outputSize: outputSize1,
            timestamp: Date()
        )
        results.append(result1)

        // --- Part 2: Pages splitPage to end ---
        let part2PageCount = pageCount - part1PageCount

        guard let dstDoc2 = mino_create_pdf_document(ctx) else {
            throw MuPDFError.documentCreationFailed
        }

        guard let graftMap2 = mino_new_graft_map(ctx, dstDoc2) else {
            mino_drop_pdf_document(ctx, dstDoc2)
            throw MuPDFError.graftMapFailed
        }

        // Graft pages splitPage-1 to pageCount-1 (0-based)
        for pageIndex in (splitPage - 1)..<pageCount {
            let result = mino_graft_page(ctx, graftMap2, -1, srcPdf, Int32(pageIndex))
            if result != 0 {
                let errorMsg = getLastError() ?? "Unknown error"
                mino_clear_error()
                mino_drop_graft_map(ctx, graftMap2)
                mino_drop_pdf_document(ctx, dstDoc2)
                throw MuPDFError.pageGraftFailed(page: pageIndex, reason: errorMsg)
            }
        }
        mino_drop_graft_map(ctx, graftMap2)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL2)

        // Save Part 2
        let saveResult2 = mino_save_pdf(ctx, dstDoc2, outputURL2.path, 3)
        mino_drop_pdf_document(ctx, dstDoc2)

        if saveResult2 != 0 {
            let errorMsg = getLastError() ?? "Unknown error"
            mino_clear_error()
            throw MuPDFError.saveFailed(reason: errorMsg)
        }

        let outputSize2 = mino_get_file_size(outputURL2.path)
        if outputSize2 < 0 {
            throw MuPDFError.saveFailed(reason: "Could not verify output file for Part 2")
        }

        let result2 = SplitResult(
            id: UUID(),
            outputURL: outputURL2,
            pageRange: part2PageCount == 1 ? "\(splitPage)" : "\(splitPage)-\(pageCount)",
            pageCount: part2PageCount,
            outputSize: outputSize2,
            timestamp: Date()
        )
        results.append(result2)

        return results
    }

    // MARK: - Helper Methods

    nonisolated private func getLastError() -> String? {
        guard let cError = mino_get_last_error() else { return nil }
        return String(cString: cError)
    }

    // MARK: - Output URL Generation

    /// Generates an output directory for split files
    static func generateOutputDirectory(for sourceURL: URL) -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Split", isDirectory: true)

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)

        return documentsDir.appendingPathComponent("\(sourceName)_\(timestamp)", isDirectory: true)
    }

    /// Generates an output URL for a range extraction
    static func generateOutputURL(
        for sourceURL: URL,
        range: PageRange
    ) -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Split", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: documentsDir,
            withIntermediateDirectories: true
        )

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        // Format: DocumentName_p3-7.pdf or DocumentName_p5.pdf
        let rangeStr = range.displayString

        return documentsDir
            .appendingPathComponent("\(sourceName)_p\(rangeStr)_\(timestamp)")
            .appendingPathExtension("pdf")
    }

    /// Generates output URLs for splitting at a page
    static func generateSplitAtPageURLs(
        for sourceURL: URL,
        splitPage: Int,
        totalPages: Int
    ) -> (part1: URL, part2: URL) {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Split", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: documentsDir,
            withIntermediateDirectories: true
        )

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)

        // Format: DocumentName_pt1.pdf and DocumentName_pt2.pdf
        let url1 = documentsDir
            .appendingPathComponent("\(sourceName)_pt1_\(timestamp)")
            .appendingPathExtension("pdf")

        let url2 = documentsDir
            .appendingPathComponent("\(sourceName)_pt2_\(timestamp)")
            .appendingPathExtension("pdf")

        return (url1, url2)
    }
}
