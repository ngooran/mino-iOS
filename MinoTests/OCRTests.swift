//
//  OCRTests.swift
//  MinoTests
//
//  The input is a scan made from the sample pages: pictures of an invoice,
//  with no text in the PDF. What the pages say is known, so the recognized
//  text can be checked.
//

import PDFKit
import XCTest
@testable import Mino

final class OCRTests: XCTestCase {

    /// A scan with `pages` pages and no text layer.
    @MainActor
    private func scan(pages: Int) throws -> URL {
        let url = Scratch.directory(for: self).appendingPathComponent("scan.pdf")
        try ScanEngine.makePDF(pages: DebugLaunch.makeSampleScanPages(count: pages), filter: .color, quality: .medium, outputURL: url)
        return url
    }

    /// Round trip and "done when": the text of a scan can be searched and
    /// selected afterwards (PDFKit is what Preview uses).
    @MainActor
    func testScanBecomesSearchable() throws {
        let source = try scan(pages: 2)
        XCTAssertEqual(PDFDocument(url: source)?.page(at: 0)?.string ?? "", "", "The scan starts without text")

        let pages = try TextRecognizer.recognize(documentURL: source)
        let output = Scratch.directory(for: self).appendingPathComponent("searchable.pdf")
        try TextRecognizer.makeSearchablePDF(documentURL: source, pages: pages, outputURL: output)

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 2)
        let first = try XCTUnwrap(document.page(at: 0)?.string)
        for expected in ["Invoice 2026-041", "Kitchen plumbing repair", "Payment is due within thirty days", "531.80"] {
            XCTAssertTrue(first.contains(expected), "Page 1 should contain “\(expected)”. Got: \(first.prefix(300))")
        }
        XCTAssertTrue(document.page(at: 1)?.string?.contains("Invoice 2026-042") == true)

        // Search finds the word on the right page, where it is printed.
        let hits = document.findString("plumbing", withOptions: .caseInsensitive)
        XCTAssertEqual(hits.count, 8, "“plumbing” is printed four times on each of the two pages")
        let hit = try XCTUnwrap(hits.first)
        let page = try XCTUnwrap(hit.pages.first)
        let bounds = hit.bounds(for: page)
        let pageBounds = page.bounds(for: .mediaBox)
        XCTAssertTrue(pageBounds.contains(bounds), "The selection lies on the page")

        // It sits where Vision saw the word: same place as the recognized box.
        let word = try XCTUnwrap(pages[0].lines.flatMap(\.words).first { $0.text.lowercased().contains("plumbing") })
        let expected = CGRect(
            x: word.box.minX * pageBounds.width, y: word.box.minY * pageBounds.height,
            width: word.box.width * pageBounds.width, height: word.box.height * pageBounds.height
        )
        XCTAssertEqual(bounds.midX, expected.midX, accuracy: 12)
        XCTAssertEqual(bounds.midY, expected.midY, accuracy: 8)
        XCTAssertEqual(bounds.width, expected.width, accuracy: expected.width * 0.25)
    }

    /// The text layer is invisible: the page looks exactly as before.
    @MainActor
    func testPageLooksTheSameAfterwards() throws {
        let source = try scan(pages: 1)
        let pages = try TextRecognizer.recognize(documentURL: source)
        let output = Scratch.directory(for: self).appendingPathComponent("searchable.pdf")
        try TextRecognizer.makeSearchablePDF(documentURL: source, pages: pages, outputURL: output)

        let before = try XCTUnwrap(Pixels.render(try XCTUnwrap(PDFDocument(url: source)?.page(at: 0)), width: 500))
        let after = try XCTUnwrap(Pixels.render(try XCTUnwrap(PDFDocument(url: output)?.page(at: 0)), width: 500))
        XCTAssertEqual(before.width, after.width)
        XCTAssertEqual(before.height, after.height)
        var different = 0
        for row in 0..<40 {
            for column in 0..<30 {
                let x = (Double(column) + 0.5) / 30
                let y = (Double(row) + 0.5) / 40
                let a = Pixels.color(in: before, x: x, y: y)
                let b = Pixels.color(in: after, x: x, y: y)
                if abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) > 12 { different += 1 }
            }
        }
        XCTAssertEqual(different, 0, "\(different) of 1200 sampled pixels changed")
    }

    /// The text layer lands where the text is shown, however the page is turned.
    func testTextLayerFollowsThePageRotation() throws {
        // A known word in the upper left of the page as it is shown.
        let box = CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.04)
        for rotation in [0, 90, 180, 270] {
            let turned = Scratch.directory(for: self).appendingPathComponent("turned.pdf")
            var page = OrganizedPage(source: .original(0))
            page.rotation = rotation
            // An empty Letter page: the fixture has text, so add the layer to a blank one.
            try PageOrganizer.save(
                documentURL: Fixture.url("text-3pages.pdf"),
                pages: [OrganizedPage(source: .blank(width: 612, height: 792))].map { var p = $0; p.rotation = rotation; return p },
                outputURL: turned
            )
            let sideways = rotation % 180 != 0
            let shown = sideways ? CGSize(width: 792, height: 612) : CGSize(width: 612, height: 792)
            let recognized = RecognizedPage(
                index: 0, size: shown,
                lines: [RecognizedLine(text: "ZEBRA", box: box, words: [RecognizedWord(text: "ZEBRA", box: box)])]
            )
            let output = Scratch.directory(for: self).appendingPathComponent("layer.pdf")
            try TextRecognizer.makeSearchablePDF(documentURL: turned, pages: [recognized], outputURL: output)

            let document = try XCTUnwrap(PDFDocument(url: output))
            let result = try XCTUnwrap(document.page(at: 0))
            XCTAssertEqual(result.rotation, rotation)
            let hit = try XCTUnwrap(document.findString("ZEBRA", withOptions: []).first, "rotation \(rotation)")
            let bounds = hit.bounds(for: result)

            // Shown coordinates (x right, y up) mapped to the unrotated page.
            let sx = box.midX * shown.width
            let sy = box.midY * shown.height
            let expected: CGPoint
            switch rotation {
            case 90: expected = CGPoint(x: 612 - sy, y: sx)
            case 180: expected = CGPoint(x: 612 - sx, y: 792 - sy)
            case 270: expected = CGPoint(x: sy, y: 792 - sx)
            default: expected = CGPoint(x: sx, y: sy)
            }
            XCTAssertEqual(bounds.midX, expected.x, accuracy: 8, "rotation \(rotation)")
            XCTAssertEqual(bounds.midY, expected.y, accuracy: 8, "rotation \(rotation)")
            // The word is as wide as its box, along the direction the text runs.
            let length = sideways ? bounds.height : bounds.width
            XCTAssertEqual(length, box.width * shown.width, accuracy: 12, "rotation \(rotation)")
        }
    }

    /// A scan that lies on its side is still read, and stays searchable.
    @MainActor
    func testSidewaysScanIsStillSearchable() throws {
        let upright = try scan(pages: 1)
        let turned = Scratch.directory(for: self).appendingPathComponent("turned.pdf")
        var page = OrganizedPage(source: .original(0))
        page.rotation = 90
        try PageOrganizer.save(documentURL: upright, pages: [page], outputURL: turned)

        let pages = try TextRecognizer.recognize(documentURL: turned)
        XCTAssertEqual(pages[0].size.width, 842, accuracy: 2)
        let output = Scratch.directory(for: self).appendingPathComponent("searchable.pdf")
        try TextRecognizer.makeSearchablePDF(documentURL: turned, pages: pages, outputURL: output)
        let text = PDFDocument(url: output)?.page(at: 0)?.string ?? ""
        print("OCR: sideways page, recognized \(pages[0].lines.count) lines; contains Kitchen: \(text.contains("Kitchen"))")
        XCTAssertTrue(text.contains("plumbing") || text.contains("Invoice"), "Got: \(text.prefix(200))")
    }

    /// Pages that already have text are not read again and get no second layer.
    func testPagesWithTextAreLeftAlone() throws {
        let source = Fixture.url("text-3pages.pdf")
        let pages = try TextRecognizer.recognize(documentURL: source)
        XCTAssertEqual(pages.count, 3)
        XCTAssertTrue(pages.allSatisfy { $0.existingText != nil && $0.lines.isEmpty })
        XCTAssertTrue(TextRecognizer.text(of: pages).contains("Plain page 2"))

        let output = Scratch.directory(for: self).appendingPathComponent("searchable.pdf")
        try TextRecognizer.makeSearchablePDF(documentURL: source, pages: pages, outputURL: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.findString("Plain page 2", withOptions: []).count, 1, "The text must not be doubled")
    }

    @MainActor
    func testTextOutputKeepsReadingOrder() throws {
        let pages = try TextRecognizer.recognize(documentURL: try scan(pages: 2))
        let text = TextRecognizer.text(of: pages)
        let heading = try XCTUnwrap(text.range(of: "Invoice 2026-041"))
        let body = try XCTUnwrap(text.range(of: "Thank you for your order"))
        let second = try XCTUnwrap(text.range(of: "Invoice 2026-042"))
        XCTAssertLessThan(heading.lowerBound, body.lowerBound)
        XCTAssertLessThan(body.lowerBound, second.lowerBound)
        XCTAssertTrue(text.contains("\n\n"), "Pages are separated by an empty line")
    }

    func testLanguagesAreOffered() {
        let languages = TextRecognizer.supportedLanguages
        XCTAssertTrue(languages.contains("en-US"), "Vision should read English: \(languages)")
        XCTAssertGreaterThan(languages.count, 5)
    }

    /// "Done when": a 20-page scan is recognized in under 30 seconds.
    /// Measured here on the simulator, not on an iPhone 15.
    @MainActor
    func testTwentyPagesAreRecognizedInUnderThirtySeconds() throws {
        let folder = Scratch.directory(for: self)
        let source = folder.appendingPathComponent("twenty.pdf")
        let samples = DebugLaunch.makeSampleScanPages(count: 10)
        try ScanEngine.makePDF(pages: samples + samples, filter: .color, quality: .medium, outputURL: source)

        let start = Date()
        let pages = try TextRecognizer.recognize(documentURL: source)
        let output = folder.appendingPathComponent("searchable.pdf")
        try TextRecognizer.makeSearchablePDF(documentURL: source, pages: pages, outputURL: output)
        let seconds = Date().timeIntervalSince(start)

        XCTAssertEqual(pages.count, 20)
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 20)
        XCTAssertTrue(PDFDocument(url: output)?.page(at: 19)?.string?.contains("Invoice 2026-050") == true)
        let growth = Double((try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int ?? 0)) /
            Double((try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int ?? 1))
        print("OCR: 20 pages in \(String(format: "%.1f", seconds)) s; searchable file is \(String(format: "%.2f", growth)) times the scan")
        XCTAssertLessThan(seconds, 30, "20 pages took \(seconds) s")
        XCTAssertLessThan(growth, 1.25, "The text layer should add little to the file")
    }

    // MARK: - App flow

    /// Recognize Text is Pro; in Scan to PDF only the searchable option is.
    @MainActor
    func testRecognitionAsksForProAtTheFinalButton() throws {
        let appState = AppState()
        appState.store.debugProOverride = false
        appState.usage.reset()
        let document = PDFDocumentInfo(url: Fixture.url("text-3pages.pdf"), pageCount: 3)

        appState.start(.ocr, with: [document])
        let session = try XCTUnwrap(appState.ocrSession)
        XCTAssertNil(appState.paywallReason, "Opening the tool is free")
        appState.recognizeText(session)
        XCTAssertEqual(appState.paywallReason, .tool(.ocr))
        XCTAssertEqual(session.state.phase, .configure)
        appState.paywallReason = nil

        appState.openScan()
        let scan = try XCTUnwrap(appState.scanSession)
        appState.addScanFiles(DebugLaunch.makeSampleScanPages(count: 1))
        scan.makeSearchable = true
        appState.saveScan(scan)
        XCTAssertEqual(appState.paywallReason, .searchableScan)
        XCTAssertEqual(scan.state.phase, .configure)
        appState.store.debugProOverride = nil
    }

    @MainActor
    func testSearchableScanCarriesItsText() async throws {
        let appState = AppState()
        appState.store.debugProOverride = true
        appState.openScan()
        let session = try XCTUnwrap(appState.scanSession)
        appState.addScanFiles(DebugLaunch.makeSampleScanPages(count: 1))
        session.makeSearchable = true
        appState.saveScan(session)
        for _ in 0..<1200 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(session.state.phase, .done)
        let item = try XCTUnwrap(session.state.result)
        XCTAssertEqual(item.detail, "Searchable")
        XCTAssertTrue(session.state.resultText?.contains("Invoice 2026-041") == true)
        XCTAssertTrue(PDFDocument(url: item.url)?.page(at: 0)?.string?.contains("Kitchen plumbing repair") == true)
        appState.delete(item)
        appState.store.debugProOverride = nil
    }
}
