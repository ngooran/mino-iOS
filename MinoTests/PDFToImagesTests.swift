//
//  PDFToImagesTests.swift
//  MinoTests
//

import ImageIO
import PDFKit
import XCTest
@testable import Mino

final class PDFToImagesTests: XCTestCase {

    private func properties(of url: URL) throws -> (width: Int, height: Int, type: String) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let values = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            try XCTUnwrap(values[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(values[kCGImagePropertyPixelHeight] as? Int),
            try XCTUnwrap(CGImageSourceGetType(source) as String?)
        )
    }

    /// Round trip: every page of a PDF becomes a JPG at 150 dpi.
    func testExportsEveryPageAsJPG() throws {
        let directory = Scratch.directory(for: self)
        let urls = try PDFToImagesEngine.export(
            documentURL: Fixture.url("text-3pages.pdf"), pages: [1, 2, 3], format: .jpg, dpi: 150,
            baseName: "Fixture", directory: directory
        )

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Fixture - Page 1.jpg", "Fixture - Page 2.jpg", "Fixture - Page 3.jpg"])
        for url in urls {
            let image = try properties(of: url)
            // US Letter, 8.5 x 11 in, at 150 dpi.
            XCTAssertEqual(image.width, 1275)
            XCTAssertEqual(image.height, 1650)
            XCTAssertEqual(image.type, "public.jpeg")
        }
    }

    /// The pages show what the PDF shows: a white page with dark text near the top.
    func testExportedPageShowsThePageContent() throws {
        let directory = Scratch.directory(for: self)
        let url = try XCTUnwrap(PDFToImagesEngine.export(
            documentURL: Fixture.url("text-3pages.pdf"), pages: [2], format: .png, dpi: 150,
            baseName: "Fixture", directory: directory
        ).first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(Pixels.color(in: image, x: 0.9, y: 0.9).name, "white")
        // The heading sits about 0.1 down the page; scan that band for ink.
        var dark = 0
        for step in 0..<200 {
            let color = Pixels.color(in: image, x: 0.12 + Double(step) * 0.002, y: 0.103)
            if color.r < 100 { dark += 1 }
        }
        XCTAssertGreaterThan(dark, 5, "The heading should be visible in the exported page")
    }

    func testChosenPagesAsPNGAtHighResolution() throws {
        let directory = Scratch.directory(for: self)
        let urls = try PDFToImagesEngine.export(
            documentURL: Fixture.url("text-3pages.pdf"), pages: [1, 3], format: .png, dpi: 300,
            baseName: "Fixture", directory: directory
        )

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Fixture - Page 1.png", "Fixture - Page 3.png"])
        let image = try properties(of: urls[0])
        XCTAssertEqual(image.width, 2550)
        XCTAssertEqual(image.height, 3300)
        XCTAssertEqual(image.type, "public.png")
    }

    func testPageOutsideTheDocumentFails() {
        XCTAssertThrowsError(try PDFToImagesEngine.export(
            documentURL: Fixture.url("text-3pages.pdf"), pages: [4], format: .jpg, dpi: 150,
            baseName: "Fixture", directory: Scratch.directory(for: self)
        ))
    }

    /// "Done when": a 100-page export doesn't exceed memory limits. Pages are
    /// rendered one at a time, so memory must not grow with the page count.
    func testHundredPageExportStaysWithinMemory() throws {
        let folder = Scratch.directory(for: self)
        let source = folder.appendingPathComponent("hundred.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: source) { context in
            for page in 1...100 {
                context.beginPage()
                ("Page \(page)" as NSString).draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40)])
                UIColor(hue: CGFloat(page) / 100, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 60, y: 140, width: 475, height: 500))
            }
        }

        let baseline = Memory.footprint()
        let peak = PeakRecorder()
        peak.start()
        let urls = try PDFToImagesEngine.export(
            documentURL: source, pages: Array(1...100), format: .jpg, dpi: 300,
            baseName: "Hundred", directory: folder.appendingPathComponent("out", isDirectory: true)
        )
        peak.stop()

        XCTAssertEqual(urls.count, 100)
        XCTAssertEqual(urls.first?.lastPathComponent, "Hundred - Page 001.jpg")
        let growth = max(0, peak.value - baseline)
        print("PDFToImages: 100 pages at 300 dpi, peak memory growth \(growth / 1_048_576) MB")
        // One A4 page at 300 dpi is about 35 MB of pixels. 100 pages held at
        // once would be 3.5 GB; anything near one or two pages is fine.
        XCTAssertLessThan(growth, 200 * 1_048_576, "Memory grew by \(growth / 1_048_576) MB")
    }
}

/// Samples the memory footprint on a background thread while a test runs.
private final class PeakRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Int64 = 0
    private var running = false

    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    func start() {
        lock.lock()
        running = true
        peak = Memory.footprint()
        lock.unlock()
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let keepGoing = running
                peak = max(peak, Memory.footprint())
                lock.unlock()
                if !keepGoing { break }
                usleep(2_000)
            }
        }
    }

    func stop() {
        lock.lock()
        running = false
        peak = max(peak, Memory.footprint())
        lock.unlock()
    }
}
