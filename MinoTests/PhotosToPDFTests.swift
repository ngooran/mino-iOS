//
//  PhotosToPDFTests.swift
//  MinoTests
//

import PDFKit
import XCTest
@testable import Mino

final class PhotosToPDFTests: XCTestCase {

    private func photo(_ name: String) throws -> PhotoInput {
        try XCTUnwrap(PhotoInput.load(from: Fixture.url(name)), "\(name) should load")
    }

    /// Round trip: five photos in four formats become five pages that PDFKit opens.
    func testCreatesOnePagePerPhoto() throws {
        let names = ["photo-upright.jpg", "photo-rotated.jpg", "photo-upside-down.jpg", "screenshot.png", "photo.heic"]
        let photos = try names.map(photo)
        let output = Scratch.directory(for: self).appendingPathComponent("out.pdf")

        let pages = try PhotosToPDFEngine.makePDF(photos: photos, pageSize: .fit, margin: .none, outputURL: output)

        XCTAssertEqual(pages, 5)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 5)
        XCTAssertFalse(document.isEncrypted)
    }

    /// Every photo shows the way ImageIO displays it, whatever its EXIF
    /// orientation and format, and the page takes the displayed shape.
    func testOrientationIsRespected() throws {
        for name in ["photo-upright.jpg", "photo-rotated.jpg", "photo-upside-down.jpg", "screenshot.png", "photo.heic"] {
            let input = try photo(name)
            let output = Scratch.directory(for: self).appendingPathComponent("out.pdf")
            try PhotosToPDFEngine.makePDF(photos: [input], pageSize: .fit, margin: .none, outputURL: output)

            let page = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0))
            let rendered = try XCTUnwrap(Pixels.render(page))
            let expected = try XCTUnwrap(Pixels.uprightImage(at: input.url))

            XCTAssertEqual(Pixels.quadrants(of: rendered), Pixels.quadrants(of: expected), name)

            let bounds = page.bounds(for: .mediaBox)
            let shown = input.displaySize
            XCTAssertEqual(bounds.width / bounds.height, shown.width / shown.height, accuracy: 0.01, name)
            XCTAssertEqual(max(bounds.width, bounds.height), PhotosToPDFEngine.fitLongSide, accuracy: 0.5, name)
        }
    }

    /// The rotated fixture really is rotated, so the test above can't pass by accident.
    func testRotatedFixtureDiffersFromStoredPixels() throws {
        let rotated = try photo("photo-rotated.jpg")
        XCTAssertEqual(rotated.orientation, 6)
        XCTAssertEqual(rotated.displaySize, CGSize(width: 400, height: 600))
        let upright = try XCTUnwrap(Pixels.uprightImage(at: rotated.url))
        // Stored: red, green, blue, yellow. Turned a quarter clockwise: blue, red, yellow, green.
        XCTAssertEqual(Pixels.quadrants(of: upright), ["blue", "red", "yellow", "green"])
    }

    /// JPEG data goes into the PDF byte for byte: no recompression, even when rotated.
    func testJPEGIsEmbeddedUntouched() throws {
        for name in ["photo-upright.jpg", "photo-rotated.jpg"] {
            let input = try photo(name)
            let output = Scratch.directory(for: self).appendingPathComponent("out.pdf")
            try PhotosToPDFEngine.makePDF(photos: [input], pageSize: .a4, margin: .small, outputURL: output)

            let pdf = try Data(contentsOf: output)
            let jpeg = try Data(contentsOf: input.url)
            XCTAssertNotNil(pdf.range(of: jpeg), "\(name) should be inside the PDF unchanged")
        }
    }

    func testPageSizesAndMargins() throws {
        let landscape = try photo("photo-upright.jpg")   // 600 x 400
        let portrait = try photo("screenshot.png")       // 300 x 600
        let output = Scratch.directory(for: self).appendingPathComponent("out.pdf")

        try PhotosToPDFEngine.makePDF(photos: [landscape, portrait], pageSize: .a4, margin: .none, outputURL: output)
        var document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 842, height: 595))
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))

        try PhotosToPDFEngine.makePDF(photos: [portrait], pageSize: .letter, margin: .small, outputURL: output)
        document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))

        // The margin keeps the photo away from the edge: white outside, color inside.
        let rendered = try XCTUnwrap(Pixels.render(try XCTUnwrap(document.page(at: 0))))
        XCTAssertEqual(Pixels.color(in: rendered, x: 0.5, y: 0.01).name, "white")
        XCTAssertEqual(Pixels.color(in: rendered, x: 0.5, y: 0.99).name, "white")

        let placement = PhotosToPDFEngine.placement(displaySize: CGSize(width: 300, height: 600), pageSize: .letter, margin: .small)
        XCTAssertEqual(placement.image.height, 792 - 56, accuracy: 0.01)
        XCTAssertEqual(placement.image.midX, 306, accuracy: 0.01)

        let fit = PhotosToPDFEngine.placement(displaySize: CGSize(width: 600, height: 400), pageSize: .fit, margin: .small)
        XCTAssertEqual(fit.page.width, 842 + 56, accuracy: 0.01)
        XCTAssertEqual(fit.image.origin, CGPoint(x: 28, y: 28))
    }

    func testFileThatIsNotAnImageIsRejected() {
        XCTAssertNil(PhotoInput.load(from: Fixture.url("text-3pages.pdf").appendingPathExtension("missing")))
        let text = Scratch.directory(for: self).appendingPathComponent("note.jpg")
        try? Data("not an image".utf8).write(to: text)
        XCTAssertNil(PhotoInput.load(from: text))
    }

    /// "Done when": 50 photos convert in under 10 seconds. Measured here on
    /// the simulator with 12-megapixel photos, a fifth of them HEIC.
    func testFiftyPhotosConvertInUnderTenSeconds() throws {
        let folder = Scratch.directory(for: self)
        let jpeg = folder.appendingPathComponent("large.jpg")
        let heic = folder.appendingPathComponent("large.heic")
        try Self.writeLargePhoto(to: jpeg, type: "public.jpeg")
        try Self.writeLargePhoto(to: heic, type: "public.heic")

        var photos: [PhotoInput] = []
        for index in 0..<50 {
            let source = index % 5 == 4 ? heic : jpeg
            let copy = folder.appendingPathComponent("photo-\(index).\(source.pathExtension)")
            try FileManager.default.copyItem(at: source, to: copy)
            photos.append(try XCTUnwrap(PhotoInput.load(from: copy)))
        }

        let output = folder.appendingPathComponent("fifty.pdf")
        let start = Date()
        let pages = try PhotosToPDFEngine.makePDF(photos: photos, pageSize: .a4, margin: .small, outputURL: output)
        let seconds = Date().timeIntervalSince(start)

        XCTAssertEqual(pages, 50)
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 50)
        XCTAssertLessThan(seconds, 10, "50 photos took \(seconds) s")
        print("PhotosToPDF: 50 photos (12 MP, 10 HEIC) in \(String(format: "%.2f", seconds)) s")
    }

    /// A 4032 x 3024 picture with noise, so it compresses like a camera photo.
    private static func writeLargePhoto(to url: URL, type: String) throws {
        let size = CGSize(width: 4032, height: 3024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemOrange.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<150_000 {
                UIColor(white: .random(in: 0...1, using: &generator), alpha: 0.4).setFill()
                context.fill(CGRect(x: .random(in: 0..<size.width, using: &generator), y: .random(in: 0..<size.height, using: &generator), width: 6, height: 6))
            }
        }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    // MARK: - Session

    @MainActor
    func testDraggedPhotoTakesThePlaceOfItsTarget() throws {
        let session = PhotosToPDFSession()
        session.photos = try ["photo-upright.jpg", "photo-rotated.jpg", "screenshot.png"].map(photo)
        let ids = session.photos.map(\.id)

        // Last to first.
        session.move(ids[2], to: ids[0])
        XCTAssertEqual(session.photos.map(\.id), [ids[2], ids[0], ids[1]])

        // First to last.
        session.move(ids[2], to: ids[1])
        XCTAssertEqual(session.photos.map(\.id), [ids[0], ids[1], ids[2]])

        session.move(ids[0], to: ids[1])
        XCTAssertEqual(session.photos.map(\.id), [ids[1], ids[0], ids[2]])
    }
}
