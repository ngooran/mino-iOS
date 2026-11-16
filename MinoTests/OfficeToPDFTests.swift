//
//  OfficeToPDFTests.swift
//  MinoTests
//
//  The quality gate with 20 real documents is OfficeGateTests; these tests
//  cover each format and the behavior around it with small fixtures.
//

import PDFKit
import XCTest
@testable import Mino

@MainActor
final class OfficeToPDFTests: XCTestCase {

    private func convert(_ fixture: String, pageSize: OfficePageSize = .a4) async throws -> (OfficeConverter.Outcome, PDFDocument) {
        // Work on a copy, as the app does.
        let source = Scratch.directory(for: self).appendingPathComponent(fixture)
        try FileManager.default.copyItem(at: Fixture.url(fixture), to: source)
        let output = Scratch.directory(for: self).appendingPathComponent("converted.pdf")
        let outcome = try await OfficeConverter().convert(fileURL: source, pageSize: pageSize, outputURL: output)
        let document = try XCTUnwrap(PDFDocument(url: output), "PDFKit should open the result")
        XCTAssertEqual(document.pageCount, outcome.pageCount)
        return (outcome, document)
    }

    /// Round trip for a Word document: its text is in the PDF, as text, on A4 at true size.
    func testWordDocument() async throws {
        let (outcome, document) = try await convert("report.docx")
        XCTAssertEqual(outcome.layout, .document)
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
        let text = page.string ?? ""
        for expected in ["Quarterly Report", "Morgan Building Services", "Replace the oldest van.", "MARKER-END-OF-REPORT"] {
            XCTAssertTrue(text.contains(expected), "“\(expected)” missing")
        }
        // True size: the 12-point body text is about 12 points high, not shrunk to 80%.
        let line = try XCTUnwrap(document.findString("MARKER-END-OF-REPORT", withOptions: []).first)
        let height = line.bounds(for: page).height
        XCTAssertGreaterThan(height, 11.5, "Body text is \(height) pt high")
        XCTAssertLessThan(height, 17)
    }

    func testLetterPaper() async throws {
        let (_, document) = try await convert("report.docx", pageSize: .letter)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
    }

    func testRichTextCSVAndPlainText() async throws {
        for (fixture, marker) in [("report.rtf", "MARKER-END-OF-REPORT"), ("notes.csv", "MARKER-CSV"), ("notes.txt", "MARKER-TXT-END")] {
            let (_, document) = try await convert(fixture)
            XCTAssertTrue(document.string?.contains(marker) == true, "\(fixture) should contain \(marker)")
            XCTAssertEqual(document.pageCount, 1, fixture)
        }
    }

    /// One slide per page, and the page has the slide's shape.
    func testPresentationGetsOnePagePerSlide() async throws {
        let (outcome, document) = try await convert("slides.pptx")
        XCTAssertEqual(outcome.layout, .slides)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("MARKER-SLIDE-ONE") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("MARKER-SLIDE-TWO") == true)
        XCTAssertFalse(document.page(at: 0)?.string?.contains("MARKER-SLIDE-TWO") == true)
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 842)
        // A 4:3 slide.
        XCTAssertEqual(bounds.width / bounds.height, 4.0 / 3.0, accuracy: 0.02)
        // The title is where the slide has it: near the top left, not shrunk into a corner.
        let page = try XCTUnwrap(document.page(at: 0))
        let title = try XCTUnwrap(document.findString("Workshop Plan", withOptions: []).first).bounds(for: page)
        XCTAssertGreaterThan(title.height, 30, "A 40-point title on a slide stretched to the page")
        XCTAssertGreaterThan(title.minY, bounds.height * 0.7)
    }

    func testSingleSheetWorkbook() async throws {
        let (outcome, document) = try await convert("budget.xlsx")
        XCTAssertEqual(outcome.layout, .sheet)
        XCTAssertEqual(outcome.sheetCount, 0)
        XCTAssertEqual(document.pageCount, 1)
        let text = document.string ?? ""
        for expected in ["Copper pipe 15 mm", "MARKER-BUDGET-TOTAL", "620"] {
            XCTAssertTrue(text.contains(expected), "“\(expected)” missing")
        }
    }

    /// Every visible sheet is converted, in order; a hidden sheet is not.
    func testEverySheetOfAWorkbookIsConverted() async throws {
        let (outcome, document) = try await convert("three-sheets.xlsx")
        XCTAssertEqual(outcome.sheetCount, 2)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("MARKER-JANUARY") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("MARKER-MARCH") == true)
        XCTAssertFalse(document.string?.contains("MARKER-HIDDEN") == true, "A hidden sheet stays hidden")
    }

    func testOldExcelFormatWithSeveralSheets() async throws {
        let (outcome, document) = try await convert("two-sheets.xls")
        XCTAssertEqual(outcome.sheetCount, 2)
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let (hidden, _) = try await convert("two-sheets-one-hidden.xls")
        XCTAssertEqual(hidden.sheetCount, 0, "One visible sheet needs no splitting")
        print("Office: two-sheets.xls text: \((document.string ?? "").prefix(120).replacingOccurrences(of: "\n", with: " | "))")
    }

    // MARK: - Workbook splitter

    func testSplitterFindsVisibleSheets() {
        XCTAssertEqual(WorkbookSplitter.visibleSheets(in: Fixture.url("three-sheets.xlsx")), [0, 2])
        XCTAssertEqual(WorkbookSplitter.visibleSheets(in: Fixture.url("budget.xlsx")), [0])
        XCTAssertEqual(WorkbookSplitter.visibleSheets(in: Fixture.url("two-sheets.xls")), [0, 1])
        XCTAssertEqual(WorkbookSplitter.visibleSheets(in: Fixture.url("two-sheets-one-hidden.xls"))?.count, 1)
        // Not workbooks.
        XCTAssertNil(WorkbookSplitter.visibleSheets(in: Fixture.url("report.docx")))
        XCTAssertNil(WorkbookSplitter.visibleSheets(in: Fixture.url("notes.txt")))
        XCTAssertNil(WorkbookSplitter.visibleSheets(in: Fixture.url("slides.pptx")))
    }

    func testSplitterCopiesShowOneSheetAndChangeNothingElse() throws {
        let folder = Scratch.directory(for: self)

        // .xlsx: the copy is a valid archive with only the chosen sheet visible.
        for sheet in [0, 2] {
            let copy = folder.appendingPathComponent("only-\(sheet).xlsx")
            try WorkbookSplitter.writeCopy(of: Fixture.url("three-sheets.xlsx"), showingOnly: sheet, to: copy)
            XCTAssertEqual(WorkbookSplitter.visibleSheets(in: copy), [sheet])
        }
        // Showing a hidden sheet works too, when asked for.
        let hidden = folder.appendingPathComponent("only-1.xlsx")
        try WorkbookSplitter.writeCopy(of: Fixture.url("three-sheets.xlsx"), showingOnly: 1, to: hidden)
        XCTAssertEqual(WorkbookSplitter.visibleSheets(in: hidden), [1])

        // .xls: same size, and only a few bytes differ.
        let original = try Data(contentsOf: Fixture.url("two-sheets.xls"))
        for sheet in [0, 1] {
            let copy = folder.appendingPathComponent("only-\(sheet).xls")
            try WorkbookSplitter.writeCopy(of: Fixture.url("two-sheets.xls"), showingOnly: sheet, to: copy)
            XCTAssertEqual(WorkbookSplitter.visibleSheets(in: copy), [sheet])
            let changed = try Data(contentsOf: copy)
            XCTAssertEqual(changed.count, original.count)
            let different = zip(original, changed).filter { $0 != $1 }.count
            XCTAssertLessThanOrEqual(different, 6, "\(different) bytes changed")
        }

        XCTAssertThrowsError(try WorkbookSplitter.writeCopy(of: Fixture.url("three-sheets.xlsx"), showingOnly: 9, to: hidden))
        XCTAssertThrowsError(try WorkbookSplitter.writeCopy(of: Fixture.url("notes.txt"), showingOnly: 0, to: hidden))
    }

    // MARK: - Offline

    /// A web page can't run its script or load anything from the network.
    func testHTMLIsConvertedWithoutScriptsOrNetwork() async throws {
        let (_, document) = try await convert("page.html")
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("MARKER-HTML-BODY"))
        XCTAssertFalse(text.contains("SCRIPT-RAN"), "The page's own script must not run")
    }

    func testSomethingThatIsNotADocumentFails() async {
        let source = Scratch.directory(for: self).appendingPathComponent("empty.docx")
        try? Data().write(to: source)
        let output = Scratch.directory(for: self).appendingPathComponent("converted.pdf")
        do {
            _ = try await OfficeConverter().convert(fileURL: source, pageSize: .a4, outputURL: output)
            XCTFail("An empty file has nothing to convert")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    // MARK: - App flow

    func testOfficeFileOpensTheToolAndAsksForProAtTheFinalButton() async throws {
        XCTAssertEqual(Tool.officeToPDF.access, .pro)
        let appState = AppState()
        appState.store.debugProOverride = false

        await appState.receive([Fixture.url("report.docx")])
        let session = try XCTUnwrap(appState.officeSession, "A shared Word file opens Office to PDF")
        XCTAssertEqual(appState.homePath, [.tool(.officeToPDF)])
        XCTAssertEqual(session.typeBadge, "DOCX")
        XCTAssertNil(appState.paywallReason)

        appState.convertOffice(session)
        XCTAssertEqual(appState.paywallReason, .tool(.officeToPDF))
        appState.paywallReason = nil

        appState.store.debugProOverride = true
        appState.convertOffice(session)
        for _ in 0..<1200 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(session.state.phase, .done)
        let item = try XCTUnwrap(session.state.result)
        XCTAssertEqual(item.kind, .converted)
        XCTAssertEqual(item.name, "report")
        XCTAssertTrue(item.isPDF)
        XCTAssertTrue(PDFDocument(url: item.url)?.string?.contains("Quarterly Report") == true)
        appState.delete(item)
        appState.store.debugProOverride = nil
    }

    func testFileTypesOfferedAreTheOnesThatWereTested() {
        for name in ["a.docx", "a.doc", "a.xlsx", "a.xls", "a.pptx", "a.ppt", "a.rtf", "a.csv", "a.txt"] {
            XCTAssertEqual(ImportTypes.classify(URL(fileURLWithPath: "/x/\(name)")), .office, name)
        }
        for name in ["a.pages", "a.numbers", "a.key"] {
            XCTAssertEqual(ImportTypes.classify(URL(fileURLWithPath: "/x/\(name)")), .other, "\(name) was not tested, so it is not offered")
        }
    }
}
