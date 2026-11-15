//
//  ScanEngine.swift
//  Mino
//
//  Scan to PDF: turns captured page images into a compact PDF. Each page is
//  scaled to the preset's resolution, filtered (color, grayscale or black
//  and white) and stored as JPEG.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ScanFilter: String, CaseIterable, Identifiable, Sendable {
    case color
    case grayscale
    case blackAndWhite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return String(localized: "Color")
        case .grayscale: return String(localized: "Grayscale")
        case .blackAndWhite: return String(localized: "Black & White")
        }
    }
}

/// One captured page: an image file in the working folder.
nonisolated struct ScanPage: Identifiable, Hashable, Sendable {
    var id = UUID()
    var url: URL
}

nonisolated enum ScanEngine {

    /// Resolution and JPEG quality of a scan, per quality preset.
    struct Preset: Equatable {
        /// Dots per inch the page is stored at, taking the long side as 11.7 in (A4).
        var dpi: CGFloat
        /// 0...1
        var jpegQuality: CGFloat

        var maxLongSide: CGFloat { (dpi * 11.69).rounded() }
    }

    /// Scans need more detail than recompressed photos, so they have their
    /// own numbers behind the same three preset names.
    static func preset(for quality: CompressionQuality) -> Preset {
        switch quality {
        case .low: return Preset(dpi: 110, jpegQuality: 0.35)
        case .medium: return Preset(dpi: 140, jpegQuality: 0.4)
        case .high: return Preset(dpi: 200, jpegQuality: 0.65)
        }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Writes one PDF with a page per image. Returns the page count.
    @discardableResult
    static func makePDF(
        pages: [URL],
        filter: ScanFilter,
        quality: CompressionQuality,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> Int {
        guard !pages.isEmpty else { throw MuPDFError.invalidParameters }
        let preset = preset(for: quality)

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        return try MuPDF.withContext { ctx in
            guard let pdf = mino_create_pdf_document(ctx) else { throw MuPDFError.documentCreationFailed }
            defer { mino_drop_pdf_document(ctx, pdf) }

            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                let jpeg = scratch.appendingPathComponent("\(index).jpg")
                // One page at a time: decode, filter, encode, release.
                let pixels = try autoreleasepool {
                    try writeProcessedJPEG(from: page, to: jpeg, filter: filter, preset: preset)
                }
                // The page is as large as the paper was at the preset's resolution.
                let width = Float(pixels.width * 72 / preset.dpi)
                let height = Float(pixels.height * 72 / preset.dpi)
                guard mino_add_image_page(ctx, pdf, jpeg.path, width, height, 0, 0, width, height, 1) == 0 else {
                    throw MuPDFError.unknownError(String(localized: "Page \(index + 1) couldn't be added: \(MuPDF.lastError())"))
                }
                progress?(Double(index + 1) / Double(pages.count) * 0.95)
            }

            MuPDF.prepareOutput(outputURL)
            guard mino_save_pdf(ctx, pdf, outputURL.path, 0) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
            progress?(1)
            return pages.count
        }
    }

    /// Scales, filters and compresses one page. Returns its pixel size.
    @discardableResult
    static func writeProcessedJPEG(from source: URL, to destination: URL, filter: ScanFilter, preset: Preset) throws -> CGSize {
        guard let image = filteredImage(from: source, filter: filter, maxPixel: preset.maxLongSide) else {
            throw MuPDFError.unknownError(String(localized: "“\(source.lastPathComponent)” isn't an image Mino can read."))
        }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MuPDFError.saveFailed(reason: destination.lastPathComponent)
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: preset.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw MuPDFError.saveFailed(reason: destination.lastPathComponent)
        }
        return CGSize(width: image.width, height: image.height)
    }

    /// The page image, upright, no larger than `maxPixel` on its long side,
    /// with the filter applied. Also used for the thumbnails on the review screen.
    static func filteredImage(from source: URL, filter: ScanFilter, maxPixel: CGFloat) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? maxPixel
        let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? maxPixel
        // Never enlarge a small image.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel, max(width, height)),
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        if filter == .color { return scaled }

        var image = CIImage(cgImage: scaled)
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = 0
        if filter == .blackAndWhite {
            // Push paper to white and ink to black.
            controls.contrast = 2.4
            controls.brightness = 0.12
        }
        image = controls.outputImage ?? image
        // A single gray channel makes a smaller JPEG than three equal ones.
        return context.createCGImage(image, from: image.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }
}
