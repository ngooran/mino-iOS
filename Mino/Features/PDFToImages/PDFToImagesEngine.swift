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
        var width: Float = 0
        var height: Float = 0
        guard mino_get_page_size(ctx, doc, Int32(index), &width, &height) == 0, width > 0, height > 0 else {
            throw MuPDFError.unknownError(String(localized: "Page \(index + 1) couldn't be read: \(MuPDF.lastError())"))
        }
        var zoom = CGFloat(dpi) / 72
        let longSide = CGFloat(max(width, height)) * zoom
        if longSide > maxPixelSide { zoom *= maxPixelSide / longSide }

        guard let pixmap = mino_render_page(ctx, doc, Int32(index), Float(zoom)) else {
            throw MuPDFError.unknownError(String(localized: "Page \(index + 1) couldn't be rendered: \(MuPDF.lastError())"))
        }
        defer { mino_drop_pixmap(ctx, pixmap) }

        let pixelWidth = Int(mino_pixmap_width(ctx, pixmap))
        let pixelHeight = Int(mino_pixmap_height(ctx, pixmap))
        let stride = Int(mino_pixmap_stride(ctx, pixmap))
        guard let samples = mino_pixmap_samples(ctx, pixmap) else { throw MuPDFError.memoryError }

        // The pixmap owns the bytes; the image only borrows them until it is written.
        guard let provider = CGDataProvider(dataInfo: nil, data: samples, size: stride * pixelHeight, releaseData: { _, _, _ in }),
              let image = CGImage(
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                // The page is drawn on white, so the alpha channel carries nothing.
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw MuPDFError.memoryError
        }

        let type: UTType = format == .jpg ? .jpeg : .png
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw MuPDFError.saveFailed(reason: url.lastPathComponent)
        }
        let dpiValue = Double(zoom * 72)
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
