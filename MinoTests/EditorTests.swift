//
//  EditorTests.swift
//  MinoTests
//
//  The shared page editor of Fill & Sign and Edit & Annotate. The tests
//  drive the session the way the view does, with taps and drags in page
//  coordinates, then save and reopen the result with PDFKit.
//

import PDFKit
import XCTest
@testable import Mino

@MainActor
final class EditorTests: XCTestCase {

    private var signatures: SignatureStore!

    override func setUp() async throws {
        signatures = SignatureStore()
        SignatureKind.allCases.forEach(signatures.delete)
    }

    override func tearDown() async throws {
        SignatureKind.allCases.forEach(signatures.delete)
    }

    private func session(_ tool: Tool, _ fixture: String) throws -> EditorSession {
        // Work on a copy, as the importer does.
        let copy = Scratch.directory(for: self).appendingPathComponent(fixture)
        try FileManager.default.copyItem(at: Fixture.url(fixture), to: copy)
        let info = PDFDocumentInfo(url: copy, pageCount: PDFDocument(url: copy)?.pageCount ?? 0)
        return try XCTUnwrap(EditorSession(tool: tool, document: info, signatures: signatures))
    }

    /// Saves as `AppState.saveEdited` does and reopens the result.
    private func save(_ session: EditorSession) throws -> PDFDocument {
        let folder = Scratch.directory(for: self)
        let written = folder.appendingPathComponent("written.pdf")
        let flatten = session.flattensOnSave
        session.prepareForSaving()
        XCTAssertTrue(session.pdf.write(to: written))
        session.resumeEditing()
        let output = folder.appendingPathComponent("output.pdf")
        try PageEditorEngine.finish(
            source: written, flattenAnnotations: flatten, flattenForm: session.tool == .fillSign, outputURL: output
        )
        return try XCTUnwrap(PDFDocument(url: output), "PDFKit should open the result")
    }

    private func types(on page: PDFPage?) -> [String] {
        (page?.annotations ?? []).compactMap(\.type).sorted()
    }

    private func widget(_ name: String, in session: EditorSession, index: Int = 0) throws -> PDFAnnotation {
        let page = try XCTUnwrap(session.pdf.page(at: 0))
        let matches = page.annotations.filter { $0.type == "Widget" && ($0.fieldName ?? "").hasSuffix(name) }
        return try XCTUnwrap(matches.count > index ? matches[index] : nil, "No field \(name)")
    }

    private func tap(_ annotation: PDFAnnotation, in session: EditorSession) throws {
        session.tap(at: CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), on: try XCTUnwrap(annotation.page))
    }

    private func isInk(_ color: RGB) -> Bool {
        // The signature's dark blue.
        color.r < 110 && color.g < 120 && color.b > 50 && color.b < 170
    }

    // MARK: - Fill & Sign

    /// "Done when": a standard tax form can be filled, signed and reopened.
    /// The form is the IRS W-9.
    func testTaxFormIsFilledSignedAndFlattened() throws {
        let session = try session(.fillSign, "irs-w9.pdf")
        let page = try XCTUnwrap(session.pdf.page(at: 0))
        XCTAssertTrue(session.hasFormFields)
        XCTAssertFalse(session.hasChanges)

        // Name (line 1) and address: tap the field, type, done.
        try tap(try widget("f1_01[0]", in: session), in: session)
        let request = try XCTUnwrap(session.textRequest, "Tapping a text field asks for its text")
        XCTAssertFalse(request.multiline)
        XCTAssertFalse(request.title.contains("["), "Generated field names are not shown: \(request.title)")
        session.submitText("Alex Morgan")
        try tap(try widget("f1_07[0]", in: session), in: session)
        session.submitText("14 Canal Street")

        // "Individual/sole proprietor" checkbox.
        let box = try widget("c1_1[0]", in: session)
        try tap(box, in: session)
        XCTAssertEqual(box.buttonWidgetState, .onState)

        // Signature and date on the "Sign Here" line.
        signatures.save(DebugLaunch.makeSampleSignature(), for: .signature)
        session.activeTool = .signature
        session.tap(at: CGPoint(x: 220, y: 236), on: page)
        XCTAssertNil(session.activeTool, "One tap places the signature")
        session.activeTool = .date
        session.tap(at: CGPoint(x: 430, y: 240), on: page)
        XCTAssertTrue(session.hasChanges)

        let result = try save(session)
        XCTAssertEqual(result.pageCount, 6)
        let first = try XCTUnwrap(result.page(at: 0))

        // Flattened: no field and no stamp is left to change or move.
        XCTAssertFalse(types(on: first).contains("Widget"))
        XCTAssertFalse(types(on: first).contains("Stamp"))
        XCTAssertFalse(types(on: first).contains("FreeText"))

        // What was typed is on the page, where the fields were.
        let text = first.string ?? ""
        XCTAssertTrue(text.contains("Alex Morgan"), "Name missing from: \(text.prefix(200))")
        XCTAssertTrue(text.contains("14 Canal Street"))
        XCTAssertTrue(text.contains(Date().formatted(date: .long, time: .omitted)))
        XCTAssertGreaterThan(Pixels.count(on: first, in: CGRect(x: 58, y: 659, width: 200, height: 15)) { $0.isDark }, 20, "The name is drawn in its field")
        XCTAssertGreaterThan(Pixels.count(on: first, in: box.bounds.insetBy(dx: 1, dy: 1)) { $0.isDark }, 3, "The checkbox is checked")
        XCTAssertGreaterThan(Pixels.count(on: first, in: CGRect(x: 135, y: 210, width: 170, height: 55), where: isInk), 60, "The signature is drawn")

        // The rest of the form is untouched.
        XCTAssertTrue(text.contains("Request for Taxpayer"))
        XCTAssertTrue(result.page(at: 5)?.string?.contains("Page 6") == true)
    }

    /// "Done when": a rental contract (no form fields) can be signed.
    func testRentalContractIsSigned() throws {
        let session = try session(.fillSign, "rental-contract.pdf")
        let page = try XCTUnwrap(session.pdf.page(at: 1))
        XCTAssertFalse(session.hasFormFields)

        // No signature yet: the pad opens, and the signature lands where the tap was.
        session.activeTool = .signature
        session.tap(at: CGPoint(x: 220, y: 610), on: page)
        XCTAssertEqual(session.signaturePad, .signature)
        XCTAssertFalse(session.hasChanges)
        session.signatureDrawn(DebugLaunch.makeSampleSignature())
        XCTAssertNil(session.signaturePad)
        XCTAssertNotNil(signatures.image(for: .signature), "The signature is kept for next time")
        XCTAssertTrue(session.hasChanges)

        session.activeTool = .text
        session.tap(at: CGPoint(x: 120, y: 560), on: page)
        session.submitText("Amsterdam")
        session.activeTool = .check
        session.tap(at: CGPoint(x: 60, y: 700), on: page)
        session.tap(at: CGPoint(x: 60, y: 660), on: page)
        XCTAssertEqual(session.activeTool, .check, "Marks can be placed one after another")

        let result = try save(session)
        let signed = try XCTUnwrap(result.page(at: 1))
        XCTAssertEqual(types(on: signed), [], "Everything is fixed in place")
        XCTAssertTrue(signed.string?.contains("Amsterdam") == true)
        XCTAssertTrue(signed.string?.contains("Both parties agree") == true)
        XCTAssertGreaterThan(Pixels.count(on: signed, in: CGRect(x: 135, y: 585, width: 170, height: 55), where: isInk), 60)
        XCTAssertGreaterThan(Pixels.count(on: signed, in: CGRect(x: 51, y: 691, width: 18, height: 18)) { $0.isDark }, 10)
        // Page 1 was not touched.
        XCTAssertTrue(result.page(at: 0)?.string?.contains("Rental Agreement") == true)
    }

    func testClosingThePadWithoutSigningPlacesNothing() throws {
        let session = try session(.fillSign, "rental-contract.pdf")
        session.activeTool = .signature
        session.tap(at: CGPoint(x: 220, y: 610), on: try XCTUnwrap(session.pdf.page(at: 1)))
        session.signatureDrawn(nil)
        XCTAssertFalse(session.hasChanges)
        XCTAssertNil(signatures.image(for: .signature))
    }

    /// Every kind of field: text, multiline, checkbox, radio, dropdown, signature.
    func testEveryKindOfFormField() throws {
        let session = try session(.fillSign, "form.pdf")

        try tap(try widget("name", in: session), in: session)
        XCTAssertEqual(session.textRequest?.title, "Name")
        session.submitText("Sam Lee")
        XCTAssertEqual(try widget("name", in: session).widgetStringValue, "Sam Lee")

        try tap(try widget("notes", in: session), in: session)
        XCTAssertEqual(session.textRequest?.multiline, true)
        session.submitText("Ground floor.\nNo stairs.")

        let news = try widget("news", in: session)
        try tap(news, in: session)
        XCTAssertEqual(news.buttonWidgetState, .onState)
        try tap(news, in: session)
        XCTAssertEqual(news.buttonWidgetState, .offState)
        try tap(news, in: session)

        // Radio buttons: choosing one switches the other off.
        let basic = try widget("plan", in: session, index: 0)
        let premium = try widget("plan", in: session, index: 1)
        XCTAssertEqual(basic.buttonWidgetState, .onState)
        try tap(premium, in: session)
        XCTAssertEqual(premium.buttonWidgetState, .onState)
        XCTAssertEqual(basic.buttonWidgetState, .offState)
        try tap(premium, in: session)
        XCTAssertEqual(premium.buttonWidgetState, .onState, "A radio button doesn't switch off by itself")

        // Dropdown.
        try tap(try widget("country", in: session), in: session)
        let choice = try XCTUnwrap(session.choiceRequest)
        XCTAssertEqual(choice.options, ["Netherlands", "Germany", "France"])
        session.choose("France", for: choice)
        XCTAssertEqual(try widget("country", in: session).widgetStringValue, "France")

        // A signature field takes the signature, fitted inside it.
        signatures.save(DebugLaunch.makeSampleSignature(), for: .signature)
        let field = try widget("sig", in: session)
        try tap(field, in: session)
        let stamp = try XCTUnwrap(session.selected as? ImageStampAnnotation)
        XCTAssertTrue(field.bounds.contains(stamp.bounds), "\(stamp.bounds) should fit in \(field.bounds)")

        // Undo walks back through everything, redo forward again.
        while session.canUndo { session.undo() }
        XCTAssertEqual(try widget("name", in: session).widgetStringValue ?? "", "")
        XCTAssertEqual(news.buttonWidgetState, .offState)
        XCTAssertEqual(basic.buttonWidgetState, .onState)
        XCTAssertEqual(try widget("country", in: session).widgetStringValue, "Netherlands")
        XCTAssertFalse(session.hasChanges)
        while session.canRedo { session.redo() }
        XCTAssertEqual(try widget("country", in: session).widgetStringValue, "France")
        XCTAssertEqual(premium.buttonWidgetState, .onState)

        let result = try save(session)
        let page = try XCTUnwrap(result.page(at: 0))
        XCTAssertEqual(types(on: page), [])
        let text = page.string ?? ""
        for expected in ["Sam Lee", "Ground floor.", "No stairs.", "France"] {
            XCTAssertTrue(text.contains(expected), "“\(expected)” missing from: \(text)")
        }
        XCTAssertFalse(text.contains("Netherlands"))
        XCTAssertGreaterThan(Pixels.count(on: page, in: news.bounds.insetBy(dx: 3, dy: 3)) { $0.isDark }, 5, "Newsletter is checked")
        XCTAssertGreaterThan(Pixels.count(on: page, in: premium.bounds.insetBy(dx: 5, dy: 5)) { $0.isDark }, 20, "Premium is chosen")
        XCTAssertEqual(Pixels.count(on: page, in: basic.bounds.insetBy(dx: 5, dy: 5)) { $0.isDark }, 0, "Basic is no longer chosen")
        XCTAssertGreaterThan(Pixels.count(on: page, in: field.bounds, where: isInk), 60)
    }

    /// While the editor is open PDFKit's own field editing is off; the saved
    /// file must not carry that over.
    func testFieldsAreNotLeftReadOnly() throws {
        let session = try session(.fillSign, "form.pdf")
        let name = try widget("name", in: session)
        XCTAssertTrue(name.isReadOnly)
        session.prepareForSaving()
        XCTAssertFalse(name.isReadOnly)
        session.resumeEditing()
        XCTAssertTrue(name.isReadOnly)
    }

    // MARK: - Edit & Annotate

    /// Adds one of everything to page 2 of the plain fixture.
    private func annotate(_ session: EditorSession, whiteout: Bool) throws -> PDFPage {
        let page = try XCTUnwrap(session.pdf.page(at: 1))

        session.activeTool = .text
        session.tap(at: CGPoint(x: 300, y: 500), on: page)
        XCTAssertNotNil(session.textRequest)
        session.submitText("Checked by Sam")

        // Dragging across the heading highlights that line of text.
        session.activeTool = .highlight
        session.dragBegan(at: CGPoint(x: 74, y: 712), on: page)
        session.dragChanged(to: CGPoint(x: 150, y: 712))
        session.dragChanged(to: CGPoint(x: 230, y: 712))
        session.dragEnded()

        session.color = .red
        session.activeTool = .draw
        session.dragBegan(at: CGPoint(x: 100, y: 300), on: page)
        for step in 1...20 { session.dragChanged(to: CGPoint(x: 100 + CGFloat(step) * 10, y: 300)) }
        session.dragEnded()

        session.color = .green
        session.activeTool = .rectangle
        session.dragBegan(at: CGPoint(x: 350, y: 250), on: page)
        session.dragChanged(to: CGPoint(x: 500, y: 350))
        session.dragEnded()

        session.activeTool = .arrow
        session.dragBegan(at: CGPoint(x: 100, y: 150), on: page)
        session.dragChanged(to: CGPoint(x: 300, y: 200))
        session.dragEnded()

        session.pendingImage = UIImage(contentsOfFile: Fixture.url("photo-upright.jpg").path)
        session.activeTool = .image
        session.tap(at: CGPoint(x: 450, y: 520), on: page)
        XCTAssertNil(session.pendingImage)

        if whiteout {
            // Cover the body line "The quick brown fox…".
            session.activeTool = .whiteout
            session.dragBegan(at: CGPoint(x: 66, y: 650), on: page)
            session.dragChanged(to: CGPoint(x: 420, y: 674))
            session.dragEnded()
        }
        session.activeTool = nil
        return page
    }

    /// "Done when": annotations show correctly and are standard, so other
    /// apps can read and remove them.
    func testAnnotationsAreStandardAndCanBeRemovedElsewhere() throws {
        let session = try session(.edit, "text-3pages.pdf")
        _ = try annotate(session, whiteout: false)
        XCTAssertFalse(session.flattensOnSave)

        let result = try save(session)
        let page = try XCTUnwrap(result.page(at: 1))
        XCTAssertEqual(types(on: page), ["FreeText", "Highlight", "Ink", "Line", "Square", "Stamp"])
        XCTAssertEqual(page.annotations.first { $0.type == "FreeText" }?.contents, "Checked by Sam")

        // They show.
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 100, y: 296, width: 200, height: 8)) { $0.r > 180 && $0.g < 90 }, 100, "Red stroke")
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 80, y: 700, width: 150, height: 22)) { $0.r > 200 && $0.g > 170 && $0.b < 160 }, 300, "Yellow highlight")
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 80, y: 700, width: 150, height: 22)) { $0.isDark }, 30, "The text shows through the highlight")
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 346, y: 246, width: 158, height: 8)) { $0.g > 100 && $0.r < 90 }, 60, "Green rectangle")
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 400, y: 490, width: 100, height: 60)) { !$0.isWhite }, 3000, "Image")
        XCTAssertEqual(result.page(at: 0)?.annotations.count, 0)

        // Another app can take them off again: the page is then as it was.
        page.annotations.forEach(page.removeAnnotation)
        let cleaned = Scratch.directory(for: self).appendingPathComponent("cleaned.pdf")
        XCTAssertTrue(result.write(to: cleaned))
        let restored = try XCTUnwrap(PDFDocument(url: cleaned)?.page(at: 1))
        let original = try XCTUnwrap(PDFDocument(url: Fixture.url("text-3pages.pdf"))?.page(at: 1))
        XCTAssertEqual(restored.string, original.string)
        XCTAssertEqual(Pixels.count(on: restored, in: CGRect(x: 60, y: 100, width: 480, height: 520)) { !$0.isWhite }, 0)
    }

    /// Flatten on Save makes the changes part of the page.
    func testFlattenMakesChangesPermanent() throws {
        let session = try session(.edit, "text-3pages.pdf")
        _ = try annotate(session, whiteout: false)
        session.flatten = true
        let result = try save(session)
        let page = try XCTUnwrap(result.page(at: 1))
        XCTAssertEqual(types(on: page), [])
        XCTAssertTrue(page.string?.contains("Checked by Sam") == true, "Flattened text is real text")
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 100, y: 296, width: 200, height: 8)) { $0.r > 180 && $0.g < 90 }, 100)
        XCTAssertGreaterThan(Pixels.count(on: page, in: CGRect(x: 400, y: 490, width: 100, height: 60)) { !$0.isWhite }, 3000)
    }

    /// White-out covers the page, always flattens, and is honest about its
    /// limit: the covered text is hidden, not removed.
    func testWhiteoutCoversAndAlwaysFlattens() throws {
        let session = try session(.edit, "text-3pages.pdf")
        let page = try annotate(session, whiteout: true)
        XCTAssertTrue(session.hasWhiteout)
        XCTAssertTrue(session.flattensOnSave, "A cover that could be lifted off would be worse than none")
        _ = page

        let result = try save(session)
        let covered = try XCTUnwrap(result.page(at: 1))
        XCTAssertEqual(types(on: covered), [])
        XCTAssertEqual(Pixels.count(on: covered, in: CGRect(x: 70, y: 653, width: 340, height: 18)) { !$0.isWhite }, 0, "The line is covered")
        // This is why the screen warns: the words are still in the file.
        XCTAssertTrue(covered.string?.contains("quick brown fox") == true)
    }

    func testSelectionMoveResizeDeleteAndUndo() throws {
        let session = try session(.edit, "text-3pages.pdf")
        let page = try XCTUnwrap(session.pdf.page(at: 0))

        session.activeTool = .text
        session.tap(at: CGPoint(x: 200, y: 400), on: page)
        session.submitText("Note")
        let note = try XCTUnwrap(session.selected)
        XCTAssertTrue(session.selectedIsText)
        XCTAssertEqual(note.bounds.minX, 200, accuracy: 0.5)
        XCTAssertEqual(note.bounds.maxY, 400, accuracy: 0.5, "The tap is the text's top-left corner")
        // A dashed frame shows the selection; it is not one of the changes.
        XCTAssertEqual(page.annotations.count, 2)

        // Drag it: only a drag that starts on the selection moves it.
        XCTAssertFalse(session.canBeginDrag(at: CGPoint(x: 400, y: 100), on: page))
        XCTAssertTrue(session.canBeginDrag(at: CGPoint(x: 205, y: 395), on: page))
        let before = note.bounds
        session.dragBegan(at: CGPoint(x: 205, y: 395), on: page)
        session.dragChanged(to: CGPoint(x: 255, y: 365))
        session.dragEnded()
        XCTAssertEqual(note.bounds.minX, before.minX + 50, accuracy: 0.5)
        XCTAssertEqual(note.bounds.minY, before.minY - 30, accuracy: 0.5)

        // Larger text, same top-left corner.
        let moved = note.bounds
        session.resizeSelected(by: 1.2)
        XCTAssertGreaterThan(note.bounds.width, moved.width)
        XCTAssertEqual(note.bounds.maxY, moved.maxY, accuracy: 0.5)
        // PDFKit keeps whole point sizes: 14 x 1.2 = 16.8 becomes 17.
        XCTAssertEqual(note.font?.pointSize ?? 0, 16.8, accuracy: 0.5)

        session.editSelectedText()
        session.submitText("A longer note")
        XCTAssertEqual(note.contents, "A longer note")

        // Tap elsewhere deselects; tap the note selects it again.
        session.tap(at: CGPoint(x: 500, y: 100), on: page)
        XCTAssertNil(session.selected)
        XCTAssertEqual(page.annotations.count, 1)
        session.tap(at: CGPoint(x: note.bounds.midX, y: note.bounds.midY), on: page)
        XCTAssertTrue(session.selected === note)

        session.deleteSelected()
        XCTAssertEqual(page.annotations.count, 0)

        // Undo: back comes the note, then its text, size and place, then nothing.
        session.undo()
        XCTAssertEqual(page.annotations.count, 1)
        XCTAssertEqual(note.contents, "A longer note")
        session.undo()
        XCTAssertEqual(note.contents, "Note")
        session.undo()
        XCTAssertEqual(note.bounds.width, moved.width, accuracy: 0.5)
        session.undo()
        XCTAssertEqual(note.bounds.minX, before.minX, accuracy: 0.5)
        session.undo()
        XCTAssertEqual(page.annotations.count, 0)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.hasChanges)
        session.redo()
        XCTAssertEqual(page.annotations.count, 1)
    }

    /// The selection frame and a half-drawn shape never reach the saved file.
    func testSelectionFrameAndPreviewsAreNotSaved() throws {
        let session = try session(.edit, "text-3pages.pdf")
        let page = try XCTUnwrap(session.pdf.page(at: 0))
        session.activeTool = .text
        session.tap(at: CGPoint(x: 200, y: 400), on: page)
        session.submitText("Note")
        XCTAssertNotNil(session.selected)

        // A shape in mid-drag.
        session.activeTool = .rectangle
        session.dragBegan(at: CGPoint(x: 100, y: 100), on: page)
        session.dragChanged(to: CGPoint(x: 200, y: 200))
        // The note stays selected for this test: select it again as the view would not.
        session.select(page.annotations.first { $0.type == "FreeText" }, on: page)

        let result = try save(session)
        XCTAssertEqual(types(on: result.page(at: 0)), ["FreeText"])
    }

    func testATouchThatHardlyMovesDrawsNothing() throws {
        let session = try session(.edit, "text-3pages.pdf")
        let page = try XCTUnwrap(session.pdf.page(at: 0))
        session.activeTool = .rectangle
        session.dragBegan(at: CGPoint(x: 100, y: 100), on: page)
        session.dragChanged(to: CGPoint(x: 101, y: 101))
        session.dragEnded()
        XCTAssertEqual(page.annotations.count, 0)
        XCTAssertFalse(session.hasChanges)

        // With a drawing tool on, a one-finger drag draws anywhere on the page.
        XCTAssertTrue(session.canBeginDrag(at: CGPoint(x: 300, y: 300), on: page))
        session.activeTool = .text
        XCTAssertFalse(session.canBeginDrag(at: CGPoint(x: 300, y: 300), on: page), "Tap tools leave drags to scrolling")
    }

    /// On a page that is shown turned, a stamp still appears upright.
    func testStampsAppearUprightOnTurnedPages() throws {
        let folder = Scratch.directory(for: self)
        let image = try XCTUnwrap(UIImage(contentsOfFile: Fixture.url("photo-upright.jpg").path))
        // Upright, the photo's quadrants are red, green, blue, yellow.
        for rotation in [0, 90, 180, 270] {
            let turned = folder.appendingPathComponent("turned-\(rotation).pdf")
            var blank = OrganizedPage(source: .blank(width: 612, height: 792))
            blank.rotation = rotation
            try PageOrganizer.save(documentURL: Fixture.url("text-3pages.pdf"), pages: [blank], outputURL: turned)
            let info = PDFDocumentInfo(url: turned, pageCount: 1)
            let session = try XCTUnwrap(EditorSession(tool: .edit, document: info, signatures: signatures))
            let page = try XCTUnwrap(session.pdf.page(at: 0))

            session.pendingImage = image
            session.activeTool = .image
            session.tap(at: CGPoint(x: 306, y: 396), on: page)     // the middle of the page
            session.flatten = true
            let result = try XCTUnwrap(try save(session).page(at: 0))
            XCTAssertEqual(result.rotation, rotation)

            // Crop the rendering to the stamp, which sits in the middle and is 200 points wide as shown.
            let rendered = try XCTUnwrap(Pixels.render(result, width: rotation % 180 == 0 ? 612 : 792))
            let stampHeight = 200.0 * 400 / 600
            let crop = CGRect(x: Double(rendered.width) / 2 - 100, y: Double(rendered.height) / 2 - stampHeight / 2, width: 200, height: stampHeight)
            let stamp = try XCTUnwrap(rendered.cropping(to: crop.insetBy(dx: 6, dy: 6)))
            XCTAssertEqual(Pixels.quadrants(of: stamp), ["red", "green", "blue", "yellow"], "rotation \(rotation)")
        }
    }

    // MARK: - App flow

    func testSavingAsksForProAndFilesTheResult() async throws {
        let appState = AppState()
        appState.store.debugProOverride = false
        let info = PDFDocumentInfo(url: Fixture.url("rental-contract.pdf"), pageCount: 2)

        appState.start(.fillSign, with: [info])
        let session = try XCTUnwrap(appState.editorSession)
        XCTAssertEqual(appState.homePath, [.tool(.fillSign)])
        XCTAssertNil(appState.paywallReason, "Fill & Sign opens for everyone")

        session.activeTool = .date
        session.tap(at: CGPoint(x: 150, y: 520), on: try XCTUnwrap(session.pdf.page(at: 1)))
        appState.saveEdited(session)
        XCTAssertEqual(appState.paywallReason, .tool(.fillSign))
        XCTAssertEqual(session.state.phase, .configure)

        appState.paywallReason = nil
        appState.store.debugProOverride = true
        appState.saveEdited(session)
        for _ in 0..<400 where session.state.phase == .working {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(session.state.phase, .done)
        let item = try XCTUnwrap(session.state.result)
        XCTAssertEqual(item.kind, .signed)
        XCTAssertEqual(item.name, "rental-contract (signed)")
        XCTAssertEqual(item.pageCount, 2)
        XCTAssertTrue(item.url.path.contains("/Signed/"))
        appState.delete(item)
        appState.store.debugProOverride = nil
    }

    func testAPDFThatLimitsChangesIsRefused() throws {
        let appState = AppState()
        var info = PDFDocumentInfo(url: Fixture.url("text-3pages.pdf"), pageCount: 3)
        info.hasRestrictions = true
        appState.start(.edit, with: [info])
        XCTAssertNil(appState.editorSession)
        XCTAssertNotNil(appState.errorMessage)
    }

    func testSignaturesAreStoredOnTheDeviceAndCanBeDeleted() throws {
        signatures.save(DebugLaunch.makeSampleSignature(), for: .initials)
        XCTAssertEqual(signatures.count, 1)
        // A new store reads it back from StorageRoot.
        let reloaded = SignatureStore()
        XCTAssertNotNil(reloaded.image(for: .initials))
        XCTAssertNil(reloaded.image(for: .signature))
        let file = StorageRoot.documents.appendingPathComponent("Signatures/initials.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        reloaded.delete(.initials)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(SignatureStore().count, 0)
    }
}
