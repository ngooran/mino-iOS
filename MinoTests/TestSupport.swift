//
//  TestSupport.swift
//  MinoTests
//
//  Fixtures, scratch folders and pixel checks shared by the tool tests.
//  The scheme launches the test host with -demoSandbox, so nothing here
//  touches the simulator's real Mino data.
//

import ImageIO
import PDFKit
import UIKit
import XCTest
@testable import Mino

enum Fixture {
    /// A file from MinoTests/Fixtures (see Scripts/make_fixtures.swift).
    static func url(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> URL {
        let bundle = Bundle(for: FixtureAnchor.self)
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = bundle.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil) else {
            XCTFail("Missing fixture \(name)", file: file, line: line)
            return URL(fileURLWithPath: "/missing/\(name)")
        }
        return url
    }
}

private final class FixtureAnchor {}

enum Scratch {
    /// A new empty folder that is removed when the test ends.
    static func directory(for test: XCTestCase) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinoTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

struct RGB: Equatable, CustomStringConvertible {
    var r: Int
    var g: Int
    var b: Int

    var description: String { "(\(r), \(g), \(b))" }

    /// The nearest of the fixture colors, tolerant of JPEG noise.
    var name: String {
        switch (r > 128, g > 128, b > 128) {
        case (true, false, false): return "red"
        case (false, true, false): return "green"
        case (false, false, true): return "blue"
        case (true, true, false): return "yellow"
        case (true, true, true): return "white"
        case (false, false, false): return "black"
        default: return "other\(description)"
        }
    }
}

enum Pixels {
    /// Color at a point given as fractions of the width and height, with the
    /// origin at the top left.
    static func color(in image: CGImage, x: Double, y: Double) -> RGB {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let px = Double(image.width) * x
        let py = Double(image.height) * (1 - y)
        // Draw the image so the wanted pixel lands on the 1x1 context.
        context.draw(image, in: CGRect(x: -px, y: -py, width: Double(image.width), height: Double(image.height)))
        return RGB(r: Int(pixel[0]), g: Int(pixel[1]), b: Int(pixel[2]))
    }

    /// Names of the colors in the middle of the four quadrants:
    /// top-left, top-right, bottom-left, bottom-right.
    static func quadrants(of image: CGImage) -> [String] {
        [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)].map { color(in: image, x: $0.0, y: $0.1).name }
    }

    /// The image file as it should be displayed (EXIF orientation applied by ImageIO).
    static func uprightImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A PDF page drawn by PDFKit, which is independent of the MuPDF code under test.
    static func render(_ page: PDFPage, width: CGFloat = 400) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let scale = width / size.width
        let target = CGSize(width: width, height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            context.cgContext.translateBy(x: 0, y: target.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }
}

extension PDFDocument {
    /// The text of every page, in order.
    var pageTexts: [String] {
        (0..<pageCount).map { page(at: $0)?.string ?? "" }
    }
}

enum Memory {
    /// The app's memory footprint in bytes, as the system counts it against the limit.
    static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}
