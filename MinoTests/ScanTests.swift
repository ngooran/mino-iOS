//
//  ScanTests.swift
//  MinoTests
//
//  The document camera can't run in the simulator, so these tests feed the
//  engine the same sample pages as the demo screen: 2480 x 3508 photos of
//  paper with uneven light and sensor noise.
//

import ImageIO
import PDFKit
import XCTest
@testable import Mino

final class ScanTests: XCTestCase {

    @MainActor
    private func samplePages(_ count: Int) -> [URL] {
        DebugLaunch.makeSampleScanPages(count: count)
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
    }

    /// Round trip: pages in, one PDF with as many pages out, at the preset's size.
    @MainActor
    func testScanBecomesAPDFWithOnePagePerCapture() throws {
        let output = Scratch.directory(for: self).appendingPathComponent("scan.pdf")
        let count = try ScanEngine.makePDF(pages: samplePages(3), filter: .color, quality: .medium, outputURL: output)

        XCTAssertEqual(count, 3)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 3)
        // An A4 sheet: 595 x 842 points, within a point of rounding.
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 595, accuracy: 1.5)
        XCTAssertEqual(bounds.height, 842, accuracy: 1.5)
    }

    /// "Done when": a 10-page scan is under 3 MB at Balanced quality.
    @MainActor
    func testTenPageScanIsUnderThreeMegabytesAtBalanced() throws {
        let pages = samplePages(10)
        let folder = Scratch.directory(for: self)
        var sizes: [String: Int] = [:]
        for filter in ScanFilter.allCases {
            let output = folder.appendingPathComponent("\(filter.rawValue).pdf")
            try ScanEngine.makePDF(pages: pages, filter: filter, quality: .medium, outputURL: output)
            XCTAssertEqual(PDFDocument(url: output)?.pageCount, 10)
            sizes[filter.rawValue] = fileSize(output)
            XCTAssertLessThan(fileSize(output), 3_000_000, "\(filter.rawValue): \(fileSize(output)) bytes")
        }
        print("Scan: 10 pages at Balanced: color \(sizes["color"]! / 1024) KB, grayscale \(sizes["grayscale"]! / 1024) KB, black and white \(sizes["blackAndWhite"]! / 1024) KB")
    }

    @MainActor
    func testPresetsTradeSizeForDetail() throws {
        let pages = samplePages(2)
        let folder = Scratch.directory(for: self)
        var sizes: [Int] = []
        for quality in [CompressionQuality.low, .medium, .high] {
            let output = folder.appendingPathComponent("\(quality.rawValue).pdf")
            try ScanEngine.makePDF(pages: pages, filter: .color, quality: quality, outputURL: output)
            sizes.append(fileSize(output))
        }
        XCTAssertLessThan(sizes[0], sizes[1])
        XCTAssertLessThan(sizes[1], sizes[2])
        XCTAssertEqual(ScanEngine.preset(for: .medium).maxLongSide, 1637)
    }

    /// Grayscale and black and white remove the color; black and white also
    /// pushes the paper to white and the ink to black.
    @MainActor
    func testFiltersChangeThePage() throws {
        let page = samplePages(1)[0]
        let color = try XCTUnwrap(ScanEngine.filteredImage(from: page, filter: .color, maxPixel: 600))
        let gray = try XCTUnwrap(ScanEngine.filteredImage(from: page, filter: .grayscale, maxPixel: 600))
        let mono = try XCTUnwrap(ScanEngine.filteredImage(from: page, filter: .blackAndWhite, maxPixel: 600))

        XCTAssertEqual(color.colorSpace?.model, .rgb)
        XCTAssertEqual(gray.colorSpace?.model, .monochrome)
        XCTAssertEqual(mono.colorSpace?.model, .monochrome)
        XCTAssertEqual(max(color.width, color.height), 600)

        // The teal rule under the heading is colored in the original only.
        let rule = Pixels.color(in: color, x: 0.5, y: 0.155)
        XCTAssertGreaterThan(rule.b - rule.r, 20, "The sample page should have a colored rule: \(rule)")
        let grayRule = Pixels.color(in: gray, x: 0.5, y: 0.155)
        XCTAssertLessThan(abs(grayRule.b - grayRule.r), 6)

        // Empty paper near the bottom right: off-white in color, white in black and white.
        let paper = Pixels.color(in: color, x: 0.9, y: 0.86)
        let monoPaper = Pixels.color(in: mono, x: 0.9, y: 0.86)
        XCTAssertLessThan(paper.r, 245)
        XCTAssertGreaterThan(monoPaper.r, 245)
    }

    @MainActor
    func testSmallImagesAreNotEnlarged() throws {
        let small = Fixture.url("photo-upright.jpg")   // 600 x 400
        let output = Scratch.directory(for: self).appendingPathComponent("small.jpg")
        let size = try ScanEngine.writeProcessedJPEG(from: small, to: output, filter: .color, preset: ScanEngine.preset(for: .high))
        XCTAssertEqual(size, CGSize(width: 600, height: 400))
    }

    func testAFileThatIsNotAnImageFails() {
        let output = Scratch.directory(for: self).appendingPathComponent("scan.pdf")
        let text = Scratch.directory(for: self).appendingPathComponent("page.jpg")
        try? Data("not an image".utf8).write(to: text)
        XCTAssertThrowsError(try ScanEngine.makePDF(pages: [text], filter: .color, quality: .medium, outputURL: output))
        XCTAssertThrowsError(try ScanEngine.makePDF(pages: [], filter: .color, quality: .medium, outputURL: output))
    }

    // MARK: - Session

    @MainActor
    func testScanIsFreeAndRetakeReplacesAPage() async throws {
        XCTAssertEqual(Tool.scan.access, .freeAllowance)
        let appState = AppState()
        appState.store.debugProOverride = false
        appState.usage.reset()
        appState.openScan()
        let session = try XCTUnwrap(appState.scanSession)
        XCTAssertEqual(appState.homePath, [.tool(.scan)])

        let pages = samplePages(3)
        appState.addScanFiles(Array(pages.prefix(2)))
        XCTAssertEqual(session.pages.count, 2)
        let first = session.pages[0].id

        // Retake page 1: it is replaced in place.
        appState.addScanFiles([pages[2]], replacing: first)
        XCTAssertEqual(session.pages.count, 2)
        XCTAssertEqual(session.pages[0].url, pages[2])

        session.move(session.pages[1].id, to: session.pages[0].id)
        XCTAssertEqual(session.pages[1].url, pages[2])

        appState.saveScan(session)
        for _ in 0..<600 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(session.state.phase, .done)
        let item = try XCTUnwrap(session.state.result)
        XCTAssertEqual(item.kind, .scanned)
        XCTAssertEqual(item.pageCount, 2)
        XCTAssertTrue(item.name.hasPrefix("Scan "))
        XCTAssertEqual(appState.usage.remaining, 2)
        appState.delete(item)
        appState.store.debugProOverride = nil
        appState.usage.reset()
    }

    @MainActor
    func testDiscardThrowsAwayThePagesAndStartsOver() throws {
        let appState = AppState()
        appState.openScan()
        let session = try XCTUnwrap(appState.scanSession)
        // Pages from the camera live in the working folder; discarding deletes them.
        let folder = OutputLocation.workingDirectory()
        let pages = samplePages(2).enumerated().map { index, url -> URL in
            let copy = folder.appendingPathComponent("page-\(index).jpg")
            try? FileManager.default.copyItem(at: url, to: copy)
            return copy
        }
        appState.addScanFiles(pages)
        session.makeSearchable = true
        XCTAssertEqual(session.pages.count, 2)

        appState.discardScan(session)
        XCTAssertTrue(session.pages.isEmpty)
        XCTAssertFalse(session.makeSearchable)
        XCTAssertTrue(pages.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        // Still on the Scan screen, ready for a new scan; nothing was saved or counted.
        XCTAssertEqual(appState.homePath, [.tool(.scan)])
        XCTAssertNil(session.state.result)
        XCTAssertEqual(appState.camera != nil, DocumentCamera.isSupported, "The camera opens for the new scan where there is one")
        appState.camera = nil
    }
}
