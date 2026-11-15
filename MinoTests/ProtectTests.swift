//
//  ProtectTests.swift
//  MinoTests
//

import PDFKit
import XCTest
@testable import Mino

final class ProtectTests: XCTestCase {

    private var source: URL { Fixture.url("text-3pages.pdf") }

    private func protected(password: String = "s3cret", printing: Bool = true, copying: Bool = true) throws -> URL {
        let output = Scratch.directory(for: self).appendingPathComponent("protected.pdf")
        try PDFProtector.protect(
            documentURL: source, password: password, allowPrinting: printing, allowCopying: copying, outputURL: output
        )
        return output
    }

    /// Round trip and "done when": the protected file opens with the
    /// password, and not without it.
    func testProtectedFileOpensOnlyWithThePassword() throws {
        let url = try protected()
        let document = try XCTUnwrap(PDFDocument(url: url))

        XCTAssertTrue(document.isEncrypted)
        XCTAssertTrue(document.isLocked)
        XCTAssertFalse(document.unlock(withPassword: "wrong"))
        XCTAssertFalse(document.unlock(withPassword: ""))
        XCTAssertTrue(document.isLocked)

        XCTAssertTrue(document.unlock(withPassword: "s3cret"))
        XCTAssertFalse(document.isLocked)
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("Plain page 2") == true)
    }

    func testEncryptionIsAES256AndHidesTheText() throws {
        let data = try Data(contentsOf: try protected())
        // PDF 2.0 AES-256: /V 5 with a 256-bit key and the AESV3 crypt filter.
        XCTAssertNotNil(data.range(of: Data("/AESV3".utf8)))
        XCTAssertNotNil(data.range(of: Data("/V 5".utf8)))
        XCTAssertEqual(PDFProtector.encryption(of: try protected()).needsPassword, true)
    }

    func testRestrictionsApplyAfterOpening() throws {
        let document = try XCTUnwrap(PDFDocument(url: try protected(printing: true, copying: false)))
        XCTAssertTrue(document.unlock(withPassword: "s3cret"))
        XCTAssertTrue(document.allowsPrinting)
        XCTAssertFalse(document.allowsCopying)

        let open = try XCTUnwrap(PDFDocument(url: try protected(printing: false, copying: true)))
        XCTAssertTrue(open.unlock(withPassword: "s3cret"))
        XCTAssertFalse(open.allowsPrinting)
        XCTAssertTrue(open.allowsCopying)
    }

    func testWithoutRestrictionsEverythingIsAllowed() throws {
        let document = try XCTUnwrap(PDFDocument(url: try protected()))
        XCTAssertTrue(document.unlock(withPassword: "s3cret"))
        XCTAssertTrue(document.allowsPrinting)
        XCTAssertTrue(document.allowsCopying)
    }

    func testEmptyAndOverlongPasswordsAreRejected() {
        let output = Scratch.directory(for: self).appendingPathComponent("out.pdf")
        XCTAssertThrowsError(try PDFProtector.protect(documentURL: source, password: "", allowPrinting: true, allowCopying: true, outputURL: output))
        XCTAssertThrowsError(try PDFProtector.protect(
            documentURL: source, password: String(repeating: "x", count: 130), allowPrinting: true, allowCopying: true, outputURL: output
        ))
    }

    /// Characters outside ASCII are refused: MuPDF encodes them as UTF-8 (as
    /// the standard says) and PDFKit then rejects the same password.
    func testPasswordsAreLimitedToCharactersEveryAppAccepts() throws {
        let output = Scratch.directory(for: self).appendingPathComponent("out.pdf")
        XCTAssertThrowsError(try PDFProtector.protect(
            documentURL: source, password: "caf\u{E9}", allowPrinting: true, allowCopying: true, outputURL: output
        ))
        XCTAssertFalse(PDFProtector.isPortable("p\u{E4}ssword"))
        XCTAssertTrue(PDFProtector.isPortable("Tr0ub4dor & 3 {}~"))

        let document = try XCTUnwrap(PDFDocument(url: try protected(password: "Tr0ub4dor & 3 {}~")))
        XCTAssertTrue(document.unlock(withPassword: "Tr0ub4dor & 3 {}~"))
    }

    /// A PDF locked elsewhere with an accented password opens whichever way
    /// that app encoded it.
    func testAccentedPasswordsFromOtherAppsAreAccepted() throws {
        let folder = Scratch.directory(for: self)
        let utf8 = folder.appendingPathComponent("utf8.pdf")
        let latin1 = folder.appendingPathComponent("latin1.pdf")
        try MuPDF.withPDF(at: source) { ctx, _, pdf in
            XCTAssertEqual(mino_save_encrypted(ctx, pdf, utf8.path, "caf\u{E9}", "caf\u{E9}", -1), 0)
            let bytes: [CChar] = [0x63, 0x61, 0x66, CChar(bitPattern: 0xE9), 0]
            XCTAssertEqual(mino_save_encrypted(ctx, pdf, latin1.path, bytes, bytes, -1), 0)
        }
        for url in [utf8, latin1] {
            let output = folder.appendingPathComponent("unlocked-\(url.lastPathComponent)")
            try PDFProtector.unlock(documentURL: url, password: "caf\u{E9}", outputURL: output)
            XCTAssertEqual(PDFDocument(url: output)?.isEncrypted, false)
            XCTAssertThrowsError(try PDFProtector.unlock(documentURL: url, password: "cafe", outputURL: output))
        }
        // What PDFKit expects, for the record in ROADMAP.md.
        print("PROBE pdfkit opens utf8-encoded caf\u{E9}: \(PDFDocument(url: utf8)!.unlock(withPassword: "caf\u{E9}")), latin1-encoded: \(PDFDocument(url: latin1)!.unlock(withPassword: "caf\u{E9}"))")
    }

    // MARK: - Unlock

    func testUnlockSavesACopyWithoutThePassword() throws {
        let locked = try protected(copying: false)
        let output = Scratch.directory(for: self).appendingPathComponent("unlocked.pdf")

        try PDFProtector.unlock(documentURL: locked, password: "s3cret", outputURL: output)

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertFalse(document.isEncrypted)
        XCTAssertFalse(document.isLocked)
        XCTAssertTrue(document.allowsCopying)
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertTrue(document.page(at: 2)?.string?.contains("Plain page 3") == true)
        // The original is untouched.
        XCTAssertEqual(PDFDocument(url: locked)?.isLocked, true)
    }

    /// Unlock never opens a PDF whose password the person doesn't know.
    func testUnlockWithAWrongPasswordFails() throws {
        let locked = try protected()
        let output = Scratch.directory(for: self).appendingPathComponent("unlocked.pdf")

        XCTAssertThrowsError(try PDFProtector.unlock(documentURL: locked, password: "guess", outputURL: output))
        XCTAssertThrowsError(try PDFProtector.unlock(documentURL: locked, password: nil, outputURL: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testRestrictionsOnlyPDFNeedsItsPermissionsPassword() throws {
        // Opens freely, but copying is off and the owner password is "owner".
        let restricted = Scratch.directory(for: self).appendingPathComponent("restricted.pdf")
        try MuPDF.withPDF(at: source) { ctx, _, pdf in
            XCTAssertEqual(mino_save_encrypted(ctx, pdf, restricted.path, "", "owner", ~Int32(1 << 4)), 0)
        }
        let state = PDFProtector.encryption(of: restricted)
        XCTAssertTrue(state.isEncrypted)
        XCTAssertFalse(state.needsPassword)
        XCTAssertEqual(PDFDocument(url: restricted)?.allowsCopying, false)

        let output = Scratch.directory(for: self).appendingPathComponent("unlocked.pdf")
        XCTAssertThrowsError(try PDFProtector.unlock(documentURL: restricted, password: "nope", outputURL: output))
        XCTAssertThrowsError(try PDFProtector.unlock(documentURL: restricted, password: nil, outputURL: output))

        try PDFProtector.unlock(documentURL: restricted, password: "owner", outputURL: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertFalse(document.isEncrypted)
        XCTAssertTrue(document.allowsCopying)
    }

    func testUnlockingAPDFWithoutPasswordIsAnError() {
        let output = Scratch.directory(for: self).appendingPathComponent("unlocked.pdf")
        XCTAssertThrowsError(try PDFProtector.unlock(documentURL: source, password: "anything", outputURL: output))
    }

    // MARK: - Opening locked PDFs

    /// The password prompt's path: a locked PDF reports that it needs a
    /// password, a wrong one is refused, and the right one gives every tool an
    /// unlocked working copy.
    @MainActor
    func testImporterAsksForThePasswordOnce() async throws {
        let locked = try protected()
        let importer = DocumentImporter()

        var copy: URL?
        do {
            _ = try await importer.importDocument(from: locked)
            XCTFail("A locked PDF must not import without its password")
        } catch ImportError.passwordRequired(let url) {
            copy = url
        }
        let working = try XCTUnwrap(copy)

        do {
            _ = try await importer.unlock(copy: working, password: "wrong")
            XCTFail("A wrong password must be refused")
        } catch ImportError.wrongPassword {
            XCTAssertTrue(FileManager.default.fileExists(atPath: working.path), "The copy stays for another try")
        }

        let info = try await importer.unlock(copy: working, password: "s3cret")
        XCTAssertTrue(info.wasLocked)
        XCTAssertEqual(info.pageCount, 3)
        XCTAssertEqual(info.name, "protected")
        let document = try XCTUnwrap(PDFDocument(url: info.url))
        XCTAssertFalse(document.isLocked)
        XCTAssertFalse(document.isEncrypted)
    }

    @MainActor
    func testAppStatePromptsAndContinuesWithTheUnlockedCopy() async throws {
        let locked = try protected()
        let appState = AppState()

        async let imported = appState.importDocuments([locked])

        // First a wrong password, then the right one.
        try await waitForPasswordRequest(appState)
        XCTAssertEqual(appState.passwordRequest?.failed, false)
        XCTAssertEqual(appState.passwordRequest?.fileName, "protected")
        appState.submitPassword("wrong")

        try await waitForPasswordRequest(appState)
        XCTAssertEqual(appState.passwordRequest?.failed, true)
        appState.submitPassword("s3cret")

        let documents = await imported
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.wasLocked, true)
        XCTAssertNil(appState.passwordRequest)
        XCTAssertNil(appState.errorMessage)
    }

    @MainActor
    func testCancellingThePasswordPromptImportsNothing() async throws {
        let locked = try protected()
        let appState = AppState()

        async let imported = appState.importDocuments([locked])
        try await waitForPasswordRequest(appState)
        appState.submitPassword(nil)

        let documents = await imported
        XCTAssertTrue(documents.isEmpty)
        XCTAssertNil(appState.errorMessage, "Cancelling is not an error")
    }

    @MainActor
    private func waitForPasswordRequest(_ appState: AppState) async throws {
        for _ in 0..<200 {
            if appState.passwordRequest != nil { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("The password prompt did not appear")
    }
}
