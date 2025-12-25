//
//  MuPDFRenderer.swift
//  Mino
//
//  PDF page renderer using MuPDF
//

import UIKit

/// Renders PDF pages to UIImage using MuPDF
final class MuPDFRenderer: @unchecked Sendable {

    // MARK: - Properties

    private var context: UnsafeMutablePointer<fz_context>?
    private var document: UnsafeMutablePointer<fz_document>?
    private let lock = NSLock()
    private let documentURL: URL

    /// Number of pages in the document
    let pageCount: Int

    // MARK: - Initialization

    init(url: URL) throws {
        self.documentURL = url

        context = mino_create_context()
        guard let ctx = context else {
            throw MuPDFError.contextCreationFailed
        }

        document = mino_open_document(ctx, url.path)
        guard document != nil else {
            mino_drop_context(ctx)
            context = nil
            let errorMsg = String(cString: mino_get_last_error() ?? "Unknown error".withCString { $0 })
            throw MuPDFError.documentOpenFailed(path: url.path, reason: errorMsg)
        }

        pageCount = Int(mino_count_pages(ctx, document))
    }

    deinit {
        close()
    }

    // MARK: - Public Methods

    /// Closes the document and releases resources
    func close() {
        lock.lock()
        defer { lock.unlock() }

        if let ctx = context, let doc = document {
            mino_drop_document(ctx, doc)
            mino_drop_context(ctx)
        }
        context = nil
        document = nil
    }

    /// Gets the size of a page at the given index
    func pageSize(at index: Int) -> CGSize {
        lock.lock()
        defer { lock.unlock() }

        guard let ctx = context, let doc = document else { return .zero }
        guard index >= 0 && index < pageCount else { return .zero }

        var width: Float = 0
        var height: Float = 0
        let result = mino_get_page_size(ctx, doc, Int32(index), &width, &height)

        if result == 0 {
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        return .zero
    }

    /// Renders a page at the given index with the specified zoom level
    func renderPage(at index: Int, zoom: CGFloat = 1.0) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }

        guard let ctx = context, let doc = document else { return nil }
        guard index >= 0 && index < pageCount else { return nil }

        // Render page to pixmap
        guard let pixmap = mino_render_page(ctx, doc, Int32(index), Float(zoom)) else {
            return nil
        }
        defer { mino_drop_pixmap(ctx, pixmap) }

        // Get pixmap dimensions
        let width = Int(mino_pixmap_width(ctx, pixmap))
        let height = Int(mino_pixmap_height(ctx, pixmap))
        let stride = Int(mino_pixmap_stride(ctx, pixmap))

        guard let samples = mino_pixmap_samples(ctx, pixmap) else {
            return nil
        }

        // Create CGImage from pixmap data
        let dataSize = stride * height
        let data = Data(bytes: samples, count: dataSize)

        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        // MuPDF returns RGBA data
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Renders a thumbnail for a page (lower resolution for performance)
    func renderThumbnail(at index: Int, maxSize: CGFloat = 150) -> UIImage? {
        let pageSize = self.pageSize(at: index)
        guard pageSize.width > 0 && pageSize.height > 0 else { return nil }

        let scale = min(maxSize / pageSize.width, maxSize / pageSize.height)
        return renderPage(at: index, zoom: scale)
    }
}
