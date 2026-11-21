//
//  EditorSession.swift
//  Mino
//
//  State and behavior of the shared page editor. The view only reports taps
//  and drags in page coordinates; everything else happens here, so it can be
//  tested without touch input.
//

import PDFKit
import UIKit

@Observable
@MainActor
final class EditorSession: ToolSession {

    // MARK: - Requests the view presents

    /// Text to type: new text, a change to placed text, or a form field.
    struct TextRequest: Identifiable {
        enum Purpose {
            case new(page: PDFPage, point: CGPoint)
            case edit(PDFAnnotation)
            case field(PDFAnnotation)
        }
        let id = UUID()
        let title: String
        var text: String
        let multiline: Bool
        let purpose: Purpose
    }

    /// A dropdown or list field to choose from.
    struct ChoiceRequest: Identifiable {
        let id = UUID()
        let title: String
        let options: [String]
        let field: PDFAnnotation
    }

    private struct Change {
        let undo: () -> Void
        let redo: () -> Void
    }

    // MARK: - State

    let state = TaskState()
    /// `.fillSign` or `.edit`.
    let tool: Tool
    let document: PDFDocumentInfo
    let pdf: PDFDocument
    let signatures: SignatureStore

    var activeTool: EditorTool? {
        didSet {
            guard activeTool != oldValue else { return }
            // Picking a tool ends the selection. Putting the tool away after
            // placing something keeps that thing selected, ready to adjust.
            if activeTool != nil { select(nil) }
            if activeTool != .image { pendingImage = nil }
        }
    }
    var color: EditorColor = .black
    /// Stroke width of drawings and shapes, in points.
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 14
    /// Edit & Annotate: make the changes part of the page on save.
    var flatten = false

    var textRequest: TextRequest?
    var choiceRequest: ChoiceRequest?
    /// Non-nil while the signature pad is showing.
    var signaturePad: SignatureKind?
    /// A photo waiting for a tap that says where it goes.
    var pendingImage: UIImage?

    private(set) var selected: PDFAnnotation?

    /// What the person added and is on a page now. Kept here so that nothing
    /// has to look through every page of a long document after each change.
    private var ours: [ObjectIdentifier: PDFAnnotation] = [:]
    /// The form fields, found once: they don't change while editing.
    private let widgets: [PDFAnnotation]
    private var undoStack: [Change] = []
    private var redoStack: [Change] = []
    /// Where a signature goes once it has been drawn.
    private var pendingSignature: (page: PDFPage, point: CGPoint, kind: SignatureKind, field: CGRect?)?
    private var readOnlyBefore: [(PDFAnnotation, Bool)] = []

    // Drag in progress. Not observed: it changes with every movement of the
    // finger, and only the overlay (`overlayChanged`) has to follow it.
    @ObservationIgnored private var dragPage: PDFPage?
    @ObservationIgnored private var dragStart: CGPoint = .zero
    @ObservationIgnored private var dragPoints: [CGPoint] = []
    @ObservationIgnored private var preview: [PDFAnnotation] = []
    @ObservationIgnored private var moveOrigin: CGRect?
    @ObservationIgnored private var selectedPage: PDFPage?

    /// Called when `overlay` changed. The view redraws its overlay then.
    @ObservationIgnored var overlayChanged: (() -> Void)?

    // MARK: - Init

    init?(tool: Tool, document: PDFDocumentInfo, signatures: SignatureStore) {
        guard let pdf = PDFDocument(url: document.url) else { return nil }
        self.tool = tool
        self.document = document
        self.pdf = pdf
        self.signatures = signatures
        // Only Fill & Sign works with form fields.
        self.widgets = tool == .fillSign
            ? (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.flatMap { $0.annotations.filter { $0.type == "Widget" } }
            : []
        beginEditing()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasChanges: Bool { !undoStack.isEmpty }

    /// Something that covers content was added. Covering is not removing, so
    /// the result is always flattened: at least the cover can't be lifted off.
    var hasWhiteout: Bool {
        ours.values.contains { $0.type == "Square" && $0.interiorColor == .white }
    }

    var flattensOnSave: Bool { tool == .fillSign || flatten || hasWhiteout }

    var hasFormFields: Bool { !widgets.isEmpty }

    // MARK: - Overlay

    /// What the view draws over the pages. None of it is in the document.
    /// PDFKit renders a whole page again whenever an annotation is added or
    /// removed, so whatever follows the finger is drawn here instead, and the
    /// page changes once, when the finger lifts.
    struct Overlay {
        /// A shape being drawn, or the thing being moved, with its page.
        var live: (page: PDFPage, annotations: [PDFAnnotation])?
        /// The dashed frame around the selection, in page coordinates.
        var selection: (page: PDFPage, rect: CGRect)?

        var isEmpty: Bool { live == nil && selection == nil }
    }

    var overlay: Overlay {
        var result = Overlay()
        if let page = dragPage {
            if moveOrigin != nil, let selected {
                result.live = (page, [selected])
            } else if !preview.isEmpty {
                result.live = (page, preview)
            }
        }
        if let selected, let page = selectedPage {
            result.selection = (page, selected.bounds.insetBy(dx: -4, dy: -4))
        }
        return result
    }

    // MARK: - Editing sessions

    /// Mino fills form fields itself (see `tap`), so PDFKit's own field
    /// editing is switched off while the editor is open.
    private func beginEditing() {
        guard tool == .fillSign, readOnlyBefore.isEmpty else { return }
        for widget in widgets {
            readOnlyBefore.append((widget, widget.isReadOnly))
            widget.isReadOnly = true
        }
    }

    /// Removes what must not be saved: the selection frame, drag previews and
    /// the temporary read-only flags.
    func prepareForSaving() {
        cancelDrag()
        select(nil)
        for (widget, wasReadOnly) in readOnlyBefore {
            widget.isReadOnly = wasReadOnly
        }
        readOnlyBefore.removeAll()
    }

    /// Call after saving when the editor stays open.
    func resumeEditing() {
        beginEditing()
    }

    // MARK: - Taps

    /// A tap on a page, in page coordinates.
    func tap(at point: CGPoint, on page: PDFPage) {
        if let activeTool, activeTool.placesOnTap {
            place(activeTool, at: point, on: page)
            return
        }
        if let hit = ownAnnotation(at: point, on: page) {
            select(hit, on: page)
            return
        }
        select(nil)
        if tool == .fillSign, let widget = widget(at: point, on: page) {
            fill(widget, on: page)
        }
    }

    private func ownAnnotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        // Topmost first; a little slack makes thin strokes easy to hit.
        page.annotations.reversed().first {
            ours[ObjectIdentifier($0)] != nil && $0.bounds.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func widget(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.reversed().first { $0.type == "Widget" && $0.bounds.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func place(_ tool: EditorTool, at point: CGPoint, on page: PDFPage) {
        switch tool {
        case .signature, .initials:
            let kind: SignatureKind = tool == .signature ? .signature : .initials
            placeSignature(kind, at: point, on: page, fitting: nil)
        case .date:
            addText(Date().formatted(date: .long, time: .omitted), at: point, on: page)
            activeTool = nil
        case .text:
            textRequest = TextRequest(title: String(localized: "Add Text"), text: "", multiline: true, purpose: .new(page: page, point: point))
        case .check, .cross:
            let image = EditorAnnotations.markImage(tool, color: color.uiColor)
            add([EditorAnnotations.stamp(image, center: point, width: 18, pageRotation: page.rotation)], to: page)
        case .image:
            guard let image = pendingImage else { return }
            add([EditorAnnotations.stamp(image, center: point, width: 200, pageRotation: page.rotation)], to: page)
            pendingImage = nil
            activeTool = nil
        default:
            break
        }
    }

    /// Places the stored signature, or opens the pad when there is none yet.
    private func placeSignature(_ kind: SignatureKind, at point: CGPoint, on page: PDFPage, fitting field: CGRect?) {
        guard let image = signatures.image(for: kind) else {
            pendingSignature = (page, point, kind, field)
            signaturePad = kind
            return
        }
        var width: CGFloat = kind == .signature ? 170 : 70
        var center = point
        if let field {
            // Inside a signature field: as large as fits.
            let aspect = image.size.height / max(1, image.size.width)
            width = min(field.width, field.height / max(0.01, aspect))
            center = CGPoint(x: field.midX, y: field.midY)
        }
        add([EditorAnnotations.stamp(image, center: center, width: width, pageRotation: page.rotation)], to: page)
        activeTool = nil
    }

    /// Called by the signature pad. Nil means it was closed without a signature.
    func signatureDrawn(_ image: UIImage?) {
        let pending = pendingSignature
        let kind = signaturePad ?? pending?.kind ?? .signature
        pendingSignature = nil
        signaturePad = nil
        guard let image else { return }
        signatures.save(image, for: kind)
        if let pending {
            placeSignature(pending.kind, at: pending.point, on: pending.page, fitting: pending.field)
        }
    }

    private func addText(_ string: String, at point: CGPoint, on page: PDFPage) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if page.rotation % 360 == 0 {
            // The tap marks the top-left corner of the text.
            add([EditorAnnotations.text(text, at: point, fontSize: fontSize, color: color.uiColor)], to: page)
        } else {
            // Free text would lie on its side on a turned page.
            let image = EditorAnnotations.textImage(text, fontSize: fontSize, color: color.uiColor)
            let width = image.size.width / 3
            add([EditorAnnotations.stamp(image, center: point, width: width, pageRotation: page.rotation)], to: page)
        }
    }

    /// Called by the text sheet. Nil means cancelled.
    func submitText(_ text: String?) {
        guard let request = textRequest else { return }
        textRequest = nil
        guard let text else { return }
        switch request.purpose {
        case .new(let page, let point):
            addText(text, at: point, on: page)
            activeTool = nil
        case .edit(let annotation):
            guard let page = annotation.page else { return }
            let old = annotation.contents ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != old else { return }
            let apply: (String) -> Void = { [weak self] value in
                self?.mutate(annotation, on: page) {
                    let corner = CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY)
                    annotation.contents = value
                    EditorAnnotations.fit(annotation, keepingTopLeft: corner)
                }
            }
            perform(Change(undo: { apply(old) }, redo: { apply(trimmed) }))
        case .field(let field):
            setFieldValue(text, of: field)
        }
    }

    // MARK: - Form fields

    private func fill(_ widget: PDFAnnotation, on page: PDFPage) {
        switch widget.widgetFieldType {
        case .text:
            textRequest = TextRequest(
                title: fieldTitle(widget),
                text: widget.widgetStringValue ?? "",
                multiline: widget.isMultiline,
                purpose: .field(widget)
            )
        case .button:
            toggle(widget)
        case .choice:
            choiceRequest = ChoiceRequest(
                title: fieldTitle(widget),
                options: widget.choices ?? [],
                field: widget
            )
        case .signature:
            placeSignature(.signature, at: CGPoint(x: widget.bounds.midX, y: widget.bounds.midY), on: page, fitting: widget.bounds.insetBy(dx: 2, dy: 2))
        default:
            break
        }
    }

    /// A name for a field the person can read: its tooltip, or its name when
    /// that is a plain word. Generated names such as "form[0].f1_01[0]" are not shown.
    private func fieldTitle(_ widget: PDFAnnotation) -> String {
        if let tooltip = widget.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/TU")) as? String,
           !tooltip.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(tooltip.prefix(60))
        }
        if let name = widget.fieldName, !name.isEmpty, name.count <= 30,
           name.rangeOfCharacter(from: CharacterSet(charactersIn: "[]._")) == nil {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return String(localized: "Fill Field")
    }

    func setFieldValue(_ value: String, of field: PDFAnnotation) {
        let old = field.widgetStringValue ?? ""
        guard value != old else { return }
        let apply: (String) -> Void = { [weak self] text in
            // Every widget of the field shows the value.
            for widget in self?.widgets(named: field.fieldName, like: field) ?? [field] {
                widget.widgetStringValue = text
            }
            self?.redraw(field.page)
        }
        perform(Change(undo: { apply(old) }, redo: { apply(value) }))
    }

    /// Called by the choice dialog.
    func choose(_ option: String, for request: ChoiceRequest) {
        choiceRequest = nil
        setFieldValue(option, of: request.field)
    }

    private func toggle(_ widget: PDFAnnotation) {
        switch widget.widgetControlType {
        case .radioButtonControl:
            guard widget.buttonWidgetState != .onState else { return }
            let group = widgets(named: widget.fieldName, like: widget)
            let before = group.first { $0.buttonWidgetState == .onState }
            // PDFKit clears the whole group when a radio button is switched
            // off, so the others go off first and the chosen one on last.
            let choose: (PDFAnnotation?) -> Void = { [weak self] chosen in
                group.filter { $0 !== chosen }.forEach { $0.buttonWidgetState = .offState }
                chosen?.buttonWidgetState = .onState
                self?.redraw(group)
            }
            perform(Change(undo: { choose(before) }, redo: { choose(widget) }))
        case .checkBoxControl:
            let wasOn = widget.buttonWidgetState == .onState
            perform(Change(
                undo: { [weak self] in
                    widget.buttonWidgetState = wasOn ? .onState : .offState
                    self?.redraw(widget.page)
                },
                redo: { [weak self] in
                    widget.buttonWidgetState = wasOn ? .offState : .onState
                    self?.redraw(widget.page)
                }
            ))
        default:
            break
        }
    }

    /// Widgets that belong to the same field.
    private func widgets(named name: String?, like widget: PDFAnnotation) -> [PDFAnnotation] {
        guard let name, !name.isEmpty else { return [widget] }
        let group = widgets.filter { $0.fieldName == name && $0.widgetFieldType == widget.widgetFieldType }
        return group.isEmpty ? [widget] : group
    }

    // MARK: - Drags

    /// Whether a one-finger drag starting here draws or moves something.
    /// When it doesn't, the drag scrolls the document.
    func canBeginDrag(at point: CGPoint, on page: PDFPage) -> Bool {
        if let activeTool { return !activeTool.placesOnTap }
        guard let selected, selected.page === page else { return false }
        return selected.bounds.insetBy(dx: -10, dy: -10).contains(point)
    }

    func dragBegan(at point: CGPoint, on page: PDFPage) {
        dragPage = page
        dragStart = point
        dragPoints = [point]
        if activeTool == nil, let selected, selected.page === page {
            moveOrigin = selected.bounds
            // While it moves, the overlay shows it; the page is drawn again
            // only when it is put back.
            page.removeAnnotation(selected)
            overlayChanged?()
        }
    }

    func dragChanged(to point: CGPoint) {
        guard let page = dragPage else { return }
        dragPoints.append(point)
        if let origin = moveOrigin, let selected {
            selected.bounds = origin.offsetBy(dx: point.x - dragStart.x, dy: point.y - dragStart.y)
            overlayChanged?()
            return
        }
        guard let tool = activeTool else { return }
        preview = annotations(for: tool, endingAt: point, on: page, final: false)
        overlayChanged?()
    }

    func dragEnded() {
        guard let page = dragPage, let end = dragPoints.last else { return }
        defer {
            dragPage = nil
            dragPoints = []
            moveOrigin = nil
            preview = []
            overlayChanged?()
        }
        if let origin = moveOrigin, let selected {
            let final = selected.bounds
            page.addAnnotation(selected)
            guard final != origin else { return }
            let apply: (CGRect) -> Void = { [weak self] rect in
                self?.mutate(selected, on: page) { selected.bounds = rect }
                self?.overlayChanged?()
            }
            // Already moved: record it without moving again.
            undoStack.append(Change(undo: { apply(origin) }, redo: { apply(final) }))
            redoStack.removeAll()
            return
        }
        guard let tool = activeTool else { return }
        let moved = hypot(end.x - dragStart.x, end.y - dragStart.y)
        // A touch that hardly moved is not a shape.
        guard moved >= 4 || (tool == .draw && dragPoints.count > 1) else { return }
        add(annotations(for: tool, endingAt: end, on: page, final: true), to: page, selecting: false)
    }

    /// Ends a drag without adding anything. Something being moved goes back
    /// where it was.
    private func cancelDrag() {
        if let origin = moveOrigin, let selected, let page = dragPage {
            selected.bounds = origin
            page.addAnnotation(selected)
        }
        dragPage = nil
        dragPoints = []
        moveOrigin = nil
        preview = []
        overlayChanged?()
    }

    private func annotations(for tool: EditorTool, endingAt end: CGPoint, on page: PDFPage, final: Bool) -> [PDFAnnotation] {
        let rect = CGRect(
            x: min(dragStart.x, end.x), y: min(dragStart.y, end.y),
            width: abs(end.x - dragStart.x), height: abs(end.y - dragStart.y)
        )
        switch tool {
        case .draw:
            return EditorAnnotations.ink(dragPoints, color: color.uiColor, lineWidth: lineWidth).map { [$0] } ?? []
        case .highlight:
            let highlightColor = color == .black ? EditorColor.yellow.uiColor : color.uiColor
            // Follow the lines of text when there is text; otherwise mark the area.
            if final, let lines = page.selection(from: dragStart, to: end)?.selectionsByLine(), !lines.isEmpty {
                let rects = lines.map { $0.bounds(for: page) }.filter { $0.width > 1 && $0.height > 1 }
                if !rects.isEmpty {
                    return rects.map { EditorAnnotations.highlight($0, color: highlightColor) }
                }
            }
            return [EditorAnnotations.highlight(rect, color: highlightColor)]
        case .whiteout:
            return [EditorAnnotations.whiteout(rect)]
        case .rectangle, .ellipse, .line, .arrow:
            return [EditorAnnotations.shape(tool, from: dragStart, to: end, color: color.uiColor, lineWidth: lineWidth)]
        default:
            return []
        }
    }

    // MARK: - Selection

    /// The overlay draws a frame around the selection; nothing is added to the page.
    func select(_ annotation: PDFAnnotation?, on page: PDFPage? = nil) {
        if moveOrigin != nil { cancelDrag() }
        selected = annotation
        selectedPage = annotation.flatMap { page ?? $0.page }
        overlayChanged?()
    }

    var selectedIsText: Bool { selected?.type == "FreeText" }

    /// Stamps and text can be made larger and smaller.
    var canResizeSelected: Bool {
        guard let selected else { return false }
        return selected is ImageStampAnnotation || selected.type == "FreeText"
    }

    func deleteSelected() {
        guard let annotation = selected, let page = annotation.page else { return }
        select(nil)
        perform(Change(
            undo: { [weak self] in
                page.addAnnotation(annotation)
                self?.ours[ObjectIdentifier(annotation)] = annotation
            },
            redo: { [weak self] in
                page.removeAnnotation(annotation)
                self?.ours[ObjectIdentifier(annotation)] = nil
            }
        ))
    }

    /// Makes the selected stamp or text larger (factor above 1) or smaller.
    func resizeSelected(by factor: CGFloat) {
        guard let annotation = selected, let page = annotation.page, canResizeSelected else { return }
        let oldBounds = annotation.bounds
        let oldFont = annotation.font
        let apply: (CGFloat) -> Void = { [weak self] scale in
            self?.mutate(annotation, on: page) {
                if annotation.type == "FreeText", let font = oldFont {
                    let corner = CGPoint(x: oldBounds.minX, y: oldBounds.maxY)
                    annotation.font = font.withSize(min(96, max(6, font.pointSize * scale)))
                    EditorAnnotations.fit(annotation, keepingTopLeft: corner)
                } else {
                    let size = CGSize(width: oldBounds.width * scale, height: oldBounds.height * scale)
                    guard size.width >= 8, size.height >= 8, size.width <= 2000 else { return }
                    annotation.bounds = CGRect(
                        x: oldBounds.midX - size.width / 2, y: oldBounds.midY - size.height / 2,
                        width: size.width, height: size.height
                    )
                }
            }
            self?.overlayChanged?()
        }
        perform(Change(undo: { apply(1) }, redo: { apply(factor) }))
    }

    func editSelectedText() {
        guard let annotation = selected, selectedIsText else { return }
        textRequest = TextRequest(
            title: String(localized: "Edit Text"), text: annotation.contents ?? "", multiline: true, purpose: .edit(annotation)
        )
    }

    // MARK: - Changes

    /// Adds annotations as one undoable step.
    func add(_ annotations: [PDFAnnotation], to page: PDFPage, selecting: Bool = true) {
        guard !annotations.isEmpty else { return }
        perform(Change(
            undo: { [weak self] in
                annotations.forEach {
                    page.removeAnnotation($0)
                    self?.ours[ObjectIdentifier($0)] = nil
                }
                self?.select(nil)
            },
            redo: { [weak self] in
                annotations.forEach {
                    page.addAnnotation($0)
                    self?.ours[ObjectIdentifier($0)] = $0
                }
            }
        ))
        if selecting, annotations.count == 1 {
            select(annotations[0], on: page)
        }
    }

    private func perform(_ change: Change) {
        change.redo()
        undoStack.append(change)
        redoStack.removeAll()
    }

    func undo() {
        guard let change = undoStack.popLast() else { return }
        select(nil)
        change.undo()
        redoStack.append(change)
    }

    func redo() {
        guard let change = redoStack.popLast() else { return }
        select(nil)
        change.redo()
        undoStack.append(change)
    }

    /// Changes an annotation that is on a page. PDFKit on iOS redraws a page
    /// when an annotation is added or removed, not when one is changed.
    private func mutate(_ annotation: PDFAnnotation, on page: PDFPage, _ change: () -> Void) {
        page.removeAnnotation(annotation)
        change()
        page.addAnnotation(annotation)
    }

    /// Makes PDFKit draw a page again after a form field changed.
    private func redraw(_ page: PDFPage?) {
        guard let page else { return }
        let nudge = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .square, withProperties: nil)
        nudge.color = .clear
        page.addAnnotation(nudge)
        page.removeAnnotation(nudge)
    }

    private func redraw(_ widgets: [PDFAnnotation]) {
        var seen: Set<ObjectIdentifier> = []
        for page in widgets.compactMap(\.page) where seen.insert(ObjectIdentifier(page)).inserted {
            redraw(page)
        }
    }

    // MARK: - Hints

    /// One line telling the person what the next touch does.
    var hint: String {
        if selected != nil {
            return String(localized: "Drag to move it.")
        }
        switch activeTool {
        case .signature, .initials: return String(localized: "Tap where you want to sign.")
        case .date: return String(localized: "Tap where today's date should go.")
        case .text: return String(localized: "Tap where the text should start.")
        case .check, .cross: return String(localized: "Tap to place a mark. Tap again for more.")
        case .image: return pendingImage == nil ? String(localized: "Choose a photo first.") : String(localized: "Tap where the image should go.")
        case .highlight: return String(localized: "Drag over the text to highlight it.")
        case .draw: return String(localized: "Draw with one finger or Apple Pencil. Use two fingers to scroll.")
        case .whiteout: return String(localized: "Drag over what you want to cover.")
        case .rectangle, .ellipse, .line, .arrow: return String(localized: "Drag to draw the shape.")
        case nil:
            if tool == .fillSign {
                return hasFormFields
                    ? String(localized: "Tap a form field to fill it, or pick a tool.")
                    : String(localized: "Pick a tool, then tap the page.")
            }
            return String(localized: "Pick a tool, then tap or drag on the page.")
        }
    }
}
