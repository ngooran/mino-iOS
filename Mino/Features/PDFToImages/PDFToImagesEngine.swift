//
//  PDFToImagesEngine.swift
//  Mino
//
//  PDF to Images: renders the chosen pages one at a time and writes each as
//  a JPG or PNG file. Only one page is in memory at any moment.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PDFToImagesEngine {

    /// The longest side an exported image may have, in pixels. Larger pages
    /// are exported at a lower resolution instead of exhausting memory.
    static let maxPixelSide: CGFloat = 8000

    static let jpegQuality: CGFloat = 0.9

    /// Exports pages (1-based) into `directory` as "<baseName> - Page N.<ext>".
    /// Returns the files in page order.
    static func export(
        documentURL: URL,
        pages: [Int],
        format: ImageFormat,
        dpi: Int,
        baseName: String,
        directory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> [URL] {
        guard !pages.isEmpty else { throw MuPDFError.invalidParameters }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try MuPDF.withContext { ctx in
            guard let doc = mino_open_document(ctx, documentURL.path) else {
                throw MuPDFError.documentOpenFailed(path: documentURL.path, reason: MuPDF.lastError())
            }
            defer { mino_drop_document(ctx, doc) }
            let pageCount = Int(mino_count_pages(ctx, doc))
            let digits = String(pageCount).count
            var urls: [URL] = []

            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                guard page >= 1, page <= pageCount else {
                    throw MuPDFError.invalidPageRange(start: page, end: page, pageCount: pageCount)
                }
                let number = String(repeating: "0", count: max(0, digits - String(page).count)) + String(page)
                let url = directory
                    .appendingPathComponent("\(OutputLocation.sanitized(baseName)) - Page \(number)")
                    .appendingPathExtension(format.fileExtension)

                // Each page is rendered, written and released before the next one starts.
                try autoreleasepool {
                    try renderPage(ctx: ctx, doc: doc, index: page - 1, dpi: dpi, format: format, to: url)
                }
                urls.append(url)
                progress?(Double(index + 1) / Double(pages.count))
            }
            return urls
        }
    }

    private static func renderPage(
        ctx: UnsafeMutablePointer<fz_context>,
        doc: UnsafeMutablePointer<fz_document>,
        index: Int,
        dpi: Int,
        format: ImageFormat,
        to url: URL
    ) throws {
        let size = try MuPDF.pageSize(ctx, doc, index: index)
        var zoom = CGFloat(dpi) / 72
        let longSide = max(size.width, size.height) * zoom
        if longSide > maxPixelSide { zoom *= maxPixelSide / longSide }

        try MuPDF.withPageImage(ctx, doc, index: index, zoom: zoom) { image in
            try write(image, to: url, format: format, dpi: Double(zoom * 72))
        }
    }

    private static func write(_ image: CGImage, to url: URL, format: ImageFormat, dpi dpiValue: Double) throws {
        let type: UTType = format == .jpg ? .jpeg : .png
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw MuPDFError.saveFailed(reason: url.lastPathComponent)
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpiValue,
            kCGImagePropertyDPIHeight: dpiValue,
        ]
        if format == .jpg { properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MuPDFError.saveFailed(reason: url.lastPathComponent)
        }
    }
}
