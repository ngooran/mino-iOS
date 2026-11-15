//
//  ToolModels.swift
//  Mino
//
//  Options and inputs of the tools added in 2.1.
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Photos to PDF

nonisolated enum PhotoPageSize: String, CaseIterable, Identifiable, Sendable {
    case fit
    case a4
    case letter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return String(localized: "Fit to Photo")
        case .a4: return String(localized: "A4")
        case .letter: return String(localized: "Letter")
        }
    }

    /// Portrait size in points, or nil when the page follows the photo.
    var size: CGSize? {
        switch self {
        case .fit: return nil
        case .a4: return CGSize(width: 595, height: 842)
        case .letter: return CGSize(width: 612, height: 792)
        }
    }
}

nonisolated enum PhotoMargin: String, CaseIterable, Identifiable, Sendable {
    case none
    case small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .small: return String(localized: "Small")
        }
    }

    /// Margin in points on every side.
    var points: CGFloat {
        switch self {
        case .none: return 0
        case .small: return 28
        }
    }
}

/// One image chosen for Photos to PDF: a local copy and what is needed to place it.
nonisolated struct PhotoInput: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    /// Stored pixel size, before the EXIF orientation is applied.
    let pixelWidth: Int
    let pixelHeight: Int
    /// EXIF orientation, 1-8.
    let orientation: Int
    /// Uniform type identifier of the stored data, e.g. "public.jpeg".
    let typeIdentifier: String

    /// Pixel size as displayed.
    var displaySize: CGSize {
        orientation >= 5
            ? CGSize(width: pixelHeight, height: pixelWidth)
            : CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// Reads size and orientation without decoding the image. Nil when the
    /// file is not an image ImageIO can read.
    static func load(from url: URL) -> PhotoInput? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        let type = (CGImageSourceGetType(source) as String?) ?? "public.image"
        return PhotoInput(
            id: UUID(),
            url: url,
            pixelWidth: width,
            pixelHeight: height,
            orientation: (1...8).contains(orientation) ? orientation : 1,
            typeIdentifier: type
        )
    }
}

// MARK: - PDF to Images

nonisolated enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpg
    case png

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

nonisolated enum ImageResolution: Int, CaseIterable, Identifiable, Sendable {
    case standard = 150
    case high = 300

    var id: Int { rawValue }
    var dpi: Int { rawValue }

    var title: String {
        switch self {
        case .standard: return String(localized: "Standard · 150 dpi")
        case .high: return String(localized: "High · 300 dpi")
        }
    }
}

// MARK: - Organize Pages

/// One page of the document being organized.
nonisolated struct OrganizedPage: Identifiable, Hashable, Sendable {

    enum Source: Hashable, Sendable {
        /// A page of the open document, 0-based.
        case original(Int)
        /// A new empty page, in points.
        case blank(width: Double, height: Double)
        /// A page of another PDF, 0-based.
        case external(url: URL, page: Int)
    }

    var id = UUID()
    var source: Source
    /// Clockwise degrees added to the page's own rotation: 0, 90, 180 or 270.
    var rotation = 0
}
