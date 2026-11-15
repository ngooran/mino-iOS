//
//  PhotosToPDFEngine.swift
//  Mino
//
//  Photos to PDF: one page per image. JPEG and PNG data goes into the PDF
//  untouched, so nothing is recompressed; other formats (HEIC, TIFF, GIF,
//  WebP) are converted to JPEG first, because MuPDF can't read them.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PhotosToPDFEngine {

    /// Long side of a "Fit to Photo" page, in points (the long side of A4).
    static let fitLongSide: CGFloat = 842

    /// JPEG quality for formats that have to be converted.
    static let transcodeQuality: CGFloat = 0.9

    /// Where a photo goes on its page.
    struct Placement: Equatable {
        var page: CGSize
        var image: CGRect
    }

    /// Page size and image rectangle (origin at the bottom left) for a photo.
    static func placement(displaySize: CGSize, pageSize: PhotoPageSize, margin: PhotoMargin) -> Placement {
        let width = max(1, displaySize.width)
        let height = max(1, displaySize.height)
        let inset = margin.points

        guard let portrait = pageSize.size else {
            // The page takes the photo's shape; the margin is added around it.
            let scale = fitLongSide / max(width, height)
            let image = CGSize(width: width * scale, height: height * scale)
            return Placement(
                page: CGSize(width: image.width + inset * 2, height: image.height + inset * 2),
                image: CGRect(x: inset, y: inset, width: image.width, height: image.height)
            )
        }

        // Landscape photos get a landscape page.
        let page = width > height ? CGSize(width: portrait.height, height: portrait.width) : portrait
        let available = CGSize(width: page.width - inset * 2, height: page.height - inset * 2)
        let scale = min(available.width / width, available.height / height)
        let image = CGSize(width: width * scale, height: height * scale)
        return Placement(
            page: page,
            image: CGRect(
                x: (page.width - image.width) / 2,
                y: (page.height - image.height) / 2,
                width: image.width,
                height: image.height
            )
        )
    }

    /// Writes one PDF with a page per photo, in order. Returns the page count.
    @discardableResult
    static func makePDF(
        photos: [PhotoInput],
        pageSize: PhotoPageSize,
        margin: PhotoMargin,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> Int {
        guard !photos.isEmpty else { throw MuPDFError.invalidParameters }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        return try MuPDF.withContext { ctx in
            guard let pdf = mino_create_pdf_document(ctx) else { throw MuPDFError.documentCreationFailed }
            defer { mino_drop_pdf_document(ctx, pdf) }

            for (index, photo) in photos.enumerated() {
                try Task.checkCancellation()
                let layout = placement(displaySize: photo.displaySize, pageSize: pageSize, margin: margin)

                func addPage(path: String, orientation: Int) -> Bool {
                    mino_add_image_page(
                        ctx, pdf, path,
                        Float(layout.page.width), Float(layout.page.height),
                        Float(layout.image.minX), Float(layout.image.minY),
                        Float(layout.image.width), Float(layout.image.height),
                        Int32(orientation)
                    ) == 0
                }

                var added = embedsDirectly(photo) && addPage(path: photo.url.path, orientation: photo.orientation)
                if !added {
                    // Not a format MuPDF reads (HEIC, TIFF, WebP), or a variant
                    // it rejects: decode with ImageIO. The copy is stored upright.
                    let lossless = UTType(photo.typeIdentifier)?.conforms(to: .png) == true
                    let converted = scratch.appendingPathComponent("\(index).\(lossless ? "png" : "jpg")")
                    try transcode(photo.url, to: converted, lossless: lossless)
                    added = addPage(path: converted.path, orientation: 1)
                }
                guard added else {
                    throw MuPDFError.unknownError(
                        String(localized: "“\(photo.url.lastPathComponent)” couldn't be added: \(MuPDF.lastError())")
                    )
                }
                progress?(Double(index + 1) / Double(photos.count) * 0.95)
            }

            MuPDF.prepareOutput(outputURL)
            guard mino_save_pdf(ctx, pdf, outputURL.path, 0) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
            progress?(1)
            return photos.count
        }
    }

    /// JPEG and PNG files are embedded as they are.
    static func embedsDirectly(_ photo: PhotoInput) -> Bool {
        guard let type = UTType(photo.typeIdentifier) else { return false }
        if type.conforms(to: .jpeg) { return true }
        // PNG has no orientation that MuPDF would miss, unless EXIF says otherwise.
        return type.conforms(to: .png) && photo.orientation == 1
    }

    /// Decodes an image and writes it upright, as JPEG or (lossless) PNG.
    static func transcode(_ source: URL, to destination: URL, lossless: Bool = false) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw MuPDFError.unknownError(String(localized: "“\(source.lastPathComponent)” isn't an image Mino can read."))
        }
        // A full-size "thumbnail" applies the EXIF orientation while decoding.
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithURL(
                destination as CFURL, (lossless ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil
              ) else {
            throw MuPDFError.unknownError(String(localized: "“\(source.lastPathComponent)” isn't an image Mino can read."))
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: transcodeQuality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw MuPDFError.saveFailed(reason: String(localized: "The image couldn't be converted."))
        }
    }
}
