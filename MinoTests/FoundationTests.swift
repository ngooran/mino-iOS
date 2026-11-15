//
//  FoundationTests.swift
//  MinoTests
//
//  The 2.1 foundation: tool registry, the shared free allowance, Pro gating
//  at the final button, and the result store.
//

import XCTest
@testable import Mino

@MainActor
final class FoundationTests: XCTestCase {

    // MARK: - Registry

    /// The owner's decision (ROADMAP.md, section 5): five tools share the
    /// free allowance, everything else is Pro.
    func testFreeAndProSplit() {
        let free = Set(Tool.allCases.filter { $0.access == .freeAllowance })
        XCTAssertEqual(free, [.compress, .scan, .photosToPDF, .pdfToImages, .organize])
        XCTAssertEqual(Tool.fillSign.access, .pro)
        XCTAssertEqual(Tool.allCases.count, 13)
    }

    func testEveryToolIsDescribed() {
        for tool in Tool.allCases {
            XCTAssertFalse(tool.title.isEmpty)
            XCTAssertFalse(tool.subtitle.isEmpty)
            XCTAssertNotNil(UIImage(systemName: tool.systemImage), "\(tool) needs a valid symbol")
            XCTAssertFalse(tool.paywallMessage.isEmpty)
        }
        // Every available tool appears in exactly one category on Home.
        let shown = Tool.Category.allCases.flatMap(\.tools)
        XCTAssertEqual(shown.count, Tool.available.count)
        XCTAssertEqual(Set(shown), Set(Tool.available))
    }

    func testSearchFindsToolsByAnyWord() {
        func hits(_ query: String) -> Set<Tool> { Set(Tool.allCases.filter { $0.matches(query) }) }
        XCTAssertTrue(hits("jpg").isSuperset(of: [.photosToPDF, .pdfToImages]))
        XCTAssertTrue(hits("password").contains(.protect))
        XCTAssertTrue(hits("rotate").contains(.organize))
        XCTAssertTrue(hits("SIGN").contains(.fillSign))
        XCTAssertEqual(hits("delete pages"), [.organize])
        XCTAssertTrue(hits("zzzz").isEmpty)
    }

    func testPickerOffersOnlyToolsThatTakeAPDF() {
        XCTAssertFalse(Tool.pdfTools.contains(.photosToPDF))
        XCTAssertFalse(Tool.pdfTools.contains(.scan))
        XCTAssertTrue(Tool.pdfTools.allSatisfy { $0.input == .pdf && $0.isAvailable })
        let single = ToolPickerContext(documents: [PDFDocumentInfo(url: Fixture.url("text-3pages.pdf"), pageCount: 3)])
        XCTAssertEqual(single.tools, Tool.pdfTools)
        let several = ToolPickerContext(documents: [single.documents[0], single.documents[0]])
        XCTAssertEqual(Set(several.tools), [.compress, .merge])
    }

    func testFileClassification() {
        XCTAssertEqual(ImportTypes.classify(URL(fileURLWithPath: "/a/Report.PDF")), .pdf)
        XCTAssertEqual(ImportTypes.classify(URL(fileURLWithPath: "/a/IMG_1.HEIC")), .image)
        XCTAssertEqual(ImportTypes.classify(URL(fileURLWithPath: "/a/Budget.xlsx")), .office)
        XCTAssertEqual(ImportTypes.classify(URL(fileURLWithPath: "/a/archive.zip")), .other)
    }

    // MARK: - Free allowance and Pro gating

    func testThreeFreeActionsADayAreShared() {
        let usage = FreeUsage()
        usage.reset()
        XCTAssertEqual(FreeUsage.dailyLimit, 3)
        XCTAssertEqual(usage.remaining, 3)
        usage.recordUse()
        usage.recordUse()
        XCTAssertEqual(usage.remaining, 1)
        usage.recordUse()
        usage.recordUse()
        XCTAssertEqual(usage.remaining, 0)
    }

    func testProToolsOpenForEveryoneAndAskAtTheFinalButton() {
        let appState = AppState()
        appState.store.debugProOverride = false
        appState.usage.reset()
        let document = PDFDocumentInfo(url: Fixture.url("text-3pages.pdf"), pageCount: 3)

        // Opening a Pro tool shows its screen, not the paywall.
        appState.start(.protect, with: [document])
        XCTAssertNotNil(appState.protectSession)
        XCTAssertEqual(appState.homePath, [.tool(.protect)])
        XCTAssertNil(appState.paywallReason)

        appState.start(.merge, with: [document])
        XCTAssertEqual(appState.homePath, [.merge])
        XCTAssertNil(appState.paywallReason)

        // The final button is where Pro is asked for, with the tool's reason.
        var ran = false
        XCTAssertFalse(appState.mayRun(.protect) { ran = true })
        XCTAssertEqual(appState.paywallReason, .tool(.protect))
        XCTAssertFalse(ran)
    }

    func testFreeToolsRunUntilTheAllowanceIsUsed() {
        let appState = AppState()
        appState.store.debugProOverride = false
        appState.usage.reset()

        XCTAssertTrue(appState.mayRun(.organize) {})
        XCTAssertNil(appState.paywallReason)

        // A free tool with a Pro option asks for Pro with that option's reason.
        XCTAssertFalse(appState.mayRun(.scan, extra: .searchableScan) {})
        XCTAssertEqual(appState.paywallReason, .searchableScan)
        appState.paywallReason = nil

        (0..<3).forEach { _ in appState.usage.recordUse() }
        XCTAssertFalse(appState.mayRun(.photosToPDF) {})
        XCTAssertEqual(appState.paywallReason, .dailyLimit)

        appState.paywallReason = nil
        appState.store.debugProOverride = true
        XCTAssertTrue(appState.mayRun(.photosToPDF) {})
        XCTAssertTrue(appState.mayRun(.protect) {})
        appState.store.debugProOverride = nil
        appState.usage.reset()
    }

    /// A free tool run through AppState counts one action and files its result.
    func testRunningAFreeToolUsesOneActionAndStoresTheResult() async throws {
        let appState = AppState()
        appState.store.debugProOverride = false
        appState.usage.reset()
        let document = PDFDocumentInfo(url: Fixture.url("structured.pdf"), pageCount: 5)

        appState.start(.organize, with: [document])
        let session = try XCTUnwrap(appState.organizeSession)
        session.selection = [session.pages[0].id]
        session.rotateSelection()
        appState.saveOrganized(session)

        for _ in 0..<400 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(session.state.phase, .done)
        XCTAssertEqual(appState.usage.remaining, 2)

        let item = try XCTUnwrap(session.state.result)
        XCTAssertEqual(item.kind, .edited)
        XCTAssertEqual(item.name, "structured (edited)")
        XCTAssertEqual(item.pageCount, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertEqual(appState.files.first, item)

        // Deleting it from Files removes the file too.
        appState.delete(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertFalse(appState.files.contains(item))
        appState.store.debugProOverride = nil
        appState.usage.reset()
    }

    // MARK: - Strings

    /// Counted strings read correctly for one and for many (String Catalog plural forms).
    func testCountedStringsHaveSingularForms() {
        XCTAssertEqual(String(localized: "\(1) pages"), "1 page")
        XCTAssertEqual(String(localized: "\(3) pages"), "3 pages")
        XCTAssertEqual(String(localized: "\(1) free actions left today"), "1 free action left today")
        XCTAssertEqual(String(localized: "\(0) free actions left today"), "0 free actions left today")
        XCTAssertEqual(String(localized: "\(1) \("JPG") images"), "1 JPG image")
        XCTAssertEqual(String(localized: "\(12) \("PNG") images"), "12 PNG images")
        XCTAssertEqual(String(localized: "Create PDF (\(1) pages)"), "Create PDF (1 page)")
        XCTAssertEqual(PDFDocumentInfo(url: Fixture.url("text-3pages.pdf"), pageCount: 1).formattedPageCount, "1 page")
    }

    // MARK: - Result store

    func testResultStoreSurvivesARelaunch() throws {
        let store = ToolResultStore()
        let directory = OutputLocation.directory(folder: "Images")
        let urls = try (1...3).map { index -> URL in
            let url = directory.appendingPathComponent("Lease - Page \(index).jpg")
            try Data(repeating: UInt8(index), count: 1000).write(to: url)
            return url
        }
        let result = store.add(ToolOutput(urls: urls, kind: .converted, pageCount: 3, detail: "3 JPG images"), tool: .pdfToImages)

        // A new store reads what the first one saved.
        let reloaded = try XCTUnwrap(ToolResultStore().result(id: result.id))
        XCTAssertEqual(reloaded.urls.map(\.lastPathComponent), urls.map(\.lastPathComponent))
        XCTAssertEqual(reloaded.size, 3000)
        XCTAssertEqual(reloaded.tool, .pdfToImages)

        let item = FileItem(reloaded)
        XCTAssertEqual(item.name, "Lease")
        XCTAssertEqual(item.kind, .converted)
        XCTAssertTrue(item.isImageSet)
        XCTAssertFalse(item.isPDF)
        XCTAssertTrue(item.summary.contains("3 JPG images"))

        store.delete(id: result.id)
        XCTAssertNil(ToolResultStore().result(id: result.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "The result's folder is removed with its last file")
    }

    func testOutputsStayInsideStorageRoot() {
        let url = OutputLocation.url(folder: "Converted", fileName: "A/B: C", fileExtension: "txt")
        XCTAssertTrue(url.path.hasPrefix(StorageRoot.documents.path))
        XCTAssertEqual(url.lastPathComponent, "A-B- C.txt")
        XCTAssertEqual(OutputLocation.resolve(relativePath: OutputLocation.relativePath(of: url)).path, url.standardizedFileURL.path)
        OutputLocation.removeFile(at: url)
    }
}
