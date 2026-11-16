//
//  PDFToTextTests.swift
//  MinoTests
//
//  PDF to Word did not pass its quality gate (WordGateTests, ROADMAP.md
//  section 11), so the tool ships as PDF to Text.
//

import PDFKit
import XCTest
@testable import Mino

final class PDFToTextTests: XCTestCase {

    /// Round trip: the text of every page, in order, pages separated by an empty line.
    func testTextComesOutInReadingOrder() throws {
        let text = try PDFToWordEngine.text(of: Fixture.url("structured.pdf"), readScans: false)
        let chapters = ["Chapter Alpha", "Chapter Bravo", "Chapter Charlie", "Chapter Delta", "Chapter Echo"]
        var cursor = text.startIndex
        for chapter in chapters {
            let range = try XCTUnwrap(text.range(of: chapter, range: cursor..<text.endIndex), "\(chapter) missing or out of order")
            cursor = range.upperBound
        }
        XCTAssertTrue(text.contains("Marker: CHARLIE-3"))
        XCTAssertTrue(text.contains("\n\n"), "Pages are separated by an empty line")
        XCTAssertFalse(text.hasPrefix("\n"))
        XCTAssertFalse(text.hasSuffix("\n"))
    }

    func testTextMatchesWhatThePDFSays() throws {
        let text = try PDFToWordEngine.text(of: Fixture.url("rental-contract.pdf"), readScans: false)
        for expected in [
            "Rental Agreement", "This agreement is made between the landlord and the tenant named below",
            "4. The notice period is two months.", "Both parties agree to the terms on page 1.",
        ] {
            XCTAssertTrue(text.contains(expected), "“\(expected)” missing from: \(text)")
        }
    }

    /// Scanned pages are read with text recognition when that is switched on.
    @MainActor
    func testScannedPagesAreReadWhenAsked() throws {
        let scan = Scratch.directory(for: self).appendingPathComponent("scan.pdf")
        try ScanEngine.makePDF(pages: DebugLaunch.makeSampleScanPages(count: 1), filter: .color, quality: .medium, outputURL: scan)
        XCTAssertTrue(try PDFToWordEngine.hasPagesWithoutText(scan))
        XCTAssertFalse(try PDFToWordEngine.hasPagesWithoutText(Fixture.url("text-3pages.pdf")))

        XCTAssertEqual(try PDFToWordEngine.text(of: scan, readScans: false), "")
        let recognized = try PDFToWordEngine.text(of: scan, readScans: true)
        XCTAssertTrue(recognized.contains("Invoice 2026-041"))
        XCTAssertTrue(recognized.contains("Kitchen plumbing repair"))
    }

    @MainActor
    func testToolIsNamedForWhatItDoesAndAsksForProAtTheFinalButton() async throws {
        // The Word output failed its gate: nothing in the app may promise Word.
        XCTAssertEqual(Tool.pdfToWord.title, "PDF to Text")
        XCTAssertFalse(Tool.pdfToWord.subtitle.lowercased().contains("docx"))
        XCTAssertEqual(Tool.pdfToWord.access, .pro)
        XCTAssertTrue(Tool.pdfTools.contains(.pdfToWord))

        let appState = AppState()
        appState.store.debugProOverride = false
        let document = PDFDocumentInfo(url: Fixture.url("text-3pages.pdf"), pageCount: 3)
        appState.start(.pdfToWord, with: [document])
        let session = try XCTUnwrap(appState.textSession)
        XCTAssertNil(appState.paywallReason)
        appState.convertToText(session)
        XCTAssertEqual(appState.paywallReason, .tool(.pdfToWord))
        appState.paywallReason = nil

        appState.store.debugProOverride = true
        appState.convertToText(session)
        for _ in 0..<400 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(session.state.phase, .done)
        let item = try XCTUnwrap(session.state.result)
        XCTAssertEqual(item.url.pathExtension, "txt")
        XCTAssertEqual(item.kind, .converted)
        XCTAssertFalse(item.isPDF)
        let saved = try String(contentsOf: item.url, encoding: .utf8)
        XCTAssertTrue(saved.contains("Plain page 2"))
        XCTAssertEqual(session.state.resultText, saved)
        appState.delete(item)
        appState.store.debugProOverride = nil
    }

    @MainActor
    func testAPDFWithoutTextFailsWithAHint() async throws {
        let appState = AppState()
        appState.store.debugProOverride = true
        let scan = Scratch.directory(for: self).appendingPathComponent("scan.pdf")
        try ScanEngine.makePDF(pages: DebugLaunch.makeSampleScanPages(count: 1), filter: .color, quality: .medium, outputURL: scan)
        appState.start(.pdfToWord, with: [PDFDocumentInfo(url: scan, pageCount: 1)])
        let session = try XCTUnwrap(appState.textSession)
        session.readScans = false
        appState.convertToText(session)
        for _ in 0..<400 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard case .failed(let message) = session.state.phase else {
            return XCTFail("A scan without text recognition has no text to convert")
        }
        XCTAssertTrue(message.contains("Read Scanned Pages"))
        appState.store.debugProOverride = nil
    }

    /// The docx writer is kept for the gate. It must still produce a Word archive.
    func testWordWriterStillRunsForTheGate() throws {
        let output = Scratch.directory(for: self).appendingPathComponent("out.docx")
        let pages = try PDFToWordEngine.convertToWord(documentURL: Fixture.url("rental-contract.pdf"), outputURL: output, readScans: false)
        XCTAssertEqual(pages, 2)
        let data = try Data(contentsOf: output)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "A .docx is a ZIP archive")
        XCTAssertNotNil(data.range(of: Data("word/document.xml".utf8)))
    }
}
