//
//  OrganizeTests.swift
//  MinoTests
//
//  The structured fixture has five chapters (Alpha ... Echo), one bookmark per
//  chapter, a link from Alpha to Delta, a link from Bravo to Charlie, a text
//  field on Bravo and a checkbox on Echo.
//

import PDFKit
import XCTest
@testable import Mino

final class OrganizeTests: XCTestCase {

    private var source: URL { Fixture.url("structured.pdf") }

    private func organize(_ pages: [OrganizedPage]) throws -> PDFDocument {
        let output = Scratch.directory(for: self).appendingPathComponent("organized.pdf")
        let count = try PageOrganizer.save(documentURL: source, pages: pages, outputURL: output)
        let document = try XCTUnwrap(PDFDocument(url: output), "PDFKit should open the result")
        XCTAssertEqual(document.pageCount, count)
        return document
    }

    private func chapter(of page: PDFPage?) -> String {
        let text = page?.string ?? ""
        return ["Alpha", "Bravo", "Charlie", "Delta", "Echo"].first { text.contains("Chapter \($0)") } ?? "?"
    }

    private func links(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { $0.type == "Link" }
    }

    private func widgets(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { $0.type == "Widget" }
    }

    func testFixtureHasTheStructureTheTestsRelyOn() throws {
        let document = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertEqual(document.pageCount, 5)
        XCTAssertEqual(document.outlineRoot?.numberOfChildren, 5)
        XCTAssertEqual(links(on: document.page(at: 0)!).count, 1)
        XCTAssertEqual(links(on: document.page(at: 1)!).count, 1)
        XCTAssertEqual(widgets(on: document.page(at: 1)!).first?.widgetStringValue, "Alex Morgan")
        XCTAssertEqual(widgets(on: document.page(at: 4)!).count, 1)
    }

    /// Round trip and "done when": reorder, delete and rotate, and the
    /// bookmarks, links and form fields of the remaining pages are kept.
    func testReorderDeleteRotateKeepsBookmarksLinksAndFields() throws {
        // Charlie, Alpha (turned a quarter), Bravo, Echo. Delta is deleted.
        var alpha = OrganizedPage(source: .original(0))
        alpha.rotation = 90
        let document = try organize([
            OrganizedPage(source: .original(2)), alpha, OrganizedPage(source: .original(1)), OrganizedPage(source: .original(4)),
        ])

        XCTAssertEqual((0..<4).map { chapter(of: document.page(at: $0)) }, ["Charlie", "Alpha", "Bravo", "Echo"])
        XCTAssertEqual(document.page(at: 1)?.rotation, 90)
        XCTAssertEqual(document.page(at: 0)?.rotation, 0)
        XCTAssertFalse(document.pageTexts.joined().contains("Chapter Delta"), "The deleted page's text must be gone")

        // Bookmarks: the four kept chapters, each still pointing at its own page.
        let outline = try XCTUnwrap(document.outlineRoot)
        let bookmarks = (0..<outline.numberOfChildren).compactMap { outline.child(at: $0) }
        XCTAssertEqual(Set(bookmarks.compactMap(\.label)), ["Chapter Alpha", "Chapter Bravo", "Chapter Charlie", "Chapter Echo"])
        for bookmark in bookmarks {
            let target = chapter(of: bookmark.destination?.page)
            XCTAssertEqual("Chapter \(target)", bookmark.label, "Bookmark should still open its chapter")
        }

        // Links: Bravo → Charlie survives and still opens Charlie; Alpha → Delta is dropped.
        let bravo = try XCTUnwrap(document.page(at: 2))
        let bravoLink = try XCTUnwrap(links(on: bravo).first)
        let destination = (bravoLink.action as? PDFActionGoTo)?.destination ?? bravoLink.destination
        XCTAssertEqual(chapter(of: destination?.page), "Charlie")
        XCTAssertTrue(links(on: try XCTUnwrap(document.page(at: 1))).isEmpty, "A link to a deleted page should be removed")

        // Form fields: still fields, with their values.
        let field = try XCTUnwrap(widgets(on: bravo).first)
        XCTAssertEqual(field.fieldName, "fullName")
        XCTAssertEqual(field.widgetStringValue, "Alex Morgan")
        let checkbox = try XCTUnwrap(widgets(on: try XCTUnwrap(document.page(at: 3))).first)
        XCTAssertEqual(checkbox.fieldName, "agree")
        XCTAssertEqual(checkbox.buttonWidgetState, .onState)
    }

    /// The field stays editable: the form dictionary survived, not just the drawing.
    func testFormFieldCanStillBeFilledAfterOrganizing() throws {
        let document = try organize([OrganizedPage(source: .original(1)), OrganizedPage(source: .original(0))])
        let field = try XCTUnwrap(widgets(on: try XCTUnwrap(document.page(at: 0))).first)
        field.widgetStringValue = "Sam Lee"

        let saved = Scratch.directory(for: self).appendingPathComponent("refilled.pdf")
        XCTAssertTrue(document.write(to: saved))
        let reopened = try XCTUnwrap(PDFDocument(url: saved))
        XCTAssertEqual(widgets(on: try XCTUnwrap(reopened.page(at: 0))).first?.widgetStringValue, "Sam Lee")
    }

    func testFieldsOnDeletedPagesAreRemovedFromTheForm() throws {
        // Keep only Alpha and Charlie: both fields are on deleted pages.
        let output = Scratch.directory(for: self).appendingPathComponent("organized.pdf")
        try PageOrganizer.save(
            documentURL: source,
            pages: [OrganizedPage(source: .original(0)), OrganizedPage(source: .original(2))],
            outputURL: output
        )
        let data = try Data(contentsOf: output)
        XCTAssertNil(data.range(of: Data("Alex Morgan".utf8)), "A deleted page's field value should not stay in the file")
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 2)
    }

    func testDuplicateBlankAndInsertedPages() throws {
        let other = Fixture.url("text-3pages.pdf")
        let document = try organize([
            OrganizedPage(source: .original(0)),
            OrganizedPage(source: .original(0)),
            OrganizedPage(source: .blank(width: 595, height: 842)),
            OrganizedPage(source: .external(url: other, page: 1)),
            OrganizedPage(source: .original(1)),
            OrganizedPage(source: .original(2)),
            OrganizedPage(source: .original(3)),
            OrganizedPage(source: .original(4)),
        ])

        XCTAssertEqual(document.pageCount, 8)
        XCTAssertEqual(chapter(of: document.page(at: 0)), "Alpha")
        XCTAssertEqual(chapter(of: document.page(at: 1)), "Alpha")
        XCTAssertEqual(document.page(at: 2)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", "")
        XCTAssertEqual(document.page(at: 2)?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
        XCTAssertTrue(document.page(at: 3)?.string?.contains("Plain page 2") == true)
        XCTAssertEqual((4..<8).map { chapter(of: document.page(at: $0)) }, ["Bravo", "Charlie", "Delta", "Echo"])
        // Nothing was lost on the original pages.
        XCTAssertEqual(document.outlineRoot?.numberOfChildren, 5)
        XCTAssertEqual(widgets(on: document.page(at: 4)!).first?.widgetStringValue, "Alex Morgan")
    }

    func testRotationAddsToTheExistingRotation() throws {
        var page = OrganizedPage(source: .original(0))
        page.rotation = 270
        let once = Scratch.directory(for: self).appendingPathComponent("once.pdf")
        try PageOrganizer.save(documentURL: source, pages: [page], outputURL: once)
        XCTAssertEqual(PDFDocument(url: once)?.page(at: 0)?.rotation, 270)

        page.rotation = 180
        let twice = Scratch.directory(for: self).appendingPathComponent("twice.pdf")
        try PageOrganizer.save(documentURL: once, pages: [page], outputURL: twice)
        XCTAssertEqual(PDFDocument(url: twice)?.page(at: 0)?.rotation, 90)
    }

    func testInvalidPageFails() {
        let output = Scratch.directory(for: self).appendingPathComponent("organized.pdf")
        XCTAssertThrowsError(try PageOrganizer.save(documentURL: source, pages: [OrganizedPage(source: .original(9))], outputURL: output))
        XCTAssertThrowsError(try PageOrganizer.save(documentURL: source, pages: [], outputURL: output))
    }

    // MARK: - Session

    @MainActor
    func testSessionEditing() throws {
        let info = PDFDocumentInfo(url: source, pageCount: 5)
        let session = OrganizeSession(document: info)
        let ids = session.pages.map(\.id)
        XCTAssertFalse(session.hasChanges)

        // Move pages 2 and 3 one place earlier: 2, 3, 1, 4, 5.
        session.selection = [ids[1], ids[2]]
        session.moveSelection(by: -1)
        XCTAssertEqual(session.pages.map(\.id), [ids[1], ids[2], ids[0], ids[3], ids[4]])
        // At the start they stay put.
        session.moveSelection(by: -1)
        XCTAssertEqual(session.pages.map(\.id), [ids[1], ids[2], ids[0], ids[3], ids[4]])
        session.moveSelection(by: 1)
        XCTAssertEqual(session.pages.map(\.id), [ids[0], ids[1], ids[2], ids[3], ids[4]])

        session.rotateSelection()
        XCTAssertEqual(session.pages.map(\.rotation), [0, 90, 90, 0, 0])
        XCTAssertTrue(session.hasChanges)

        session.duplicateSelection()
        XCTAssertEqual(session.pages.count, 7)
        XCTAssertEqual(session.pages[2].source, .original(1))
        XCTAssertEqual(session.pages[2].rotation, 90)

        session.selection = [ids[4]]
        session.deleteSelection()
        XCTAssertEqual(session.pages.count, 6)
        XCTAssertTrue(session.selection.isEmpty)

        // The last page can't be deleted.
        session.selection = Set(session.pages.map(\.id))
        session.deleteSelection()
        XCTAssertEqual(session.pages.count, 6)

        session.selection = [session.pages[0].id]
        session.insertBlankPage()
        if case .blank = session.pages[1].source {} else { XCTFail("The blank page goes after the selection") }

        session.move(session.pages[6].id, to: session.pages[0].id)
        XCTAssertEqual(session.pages[0].source, .original(3))
    }
}
