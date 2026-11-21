//
//  EditorFlowView.swift
//  Mino
//
//  The shared page editor: Fill & Sign and Edit & Annotate.
//  Pick a tool → tap or drag on the page → undo or Save.
//

import PDFKit
import PencilKit
import PhotosUI
import SwiftUI

struct EditorFlowView: View {
    let tool: Tool
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.editorSession, session.tool == tool {
            EditorContent(session: session)
                .id(session.document.id)
        } else {
            NoSessionView(tool: tool)
        }
    }
}

private struct EditorContent: View {
    @Bindable var session: EditorSession
    @Environment(AppState.self) private var appState
    @State private var showsPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?

    private var isSigning: Bool { session.tool == .fillSign }

    var body: some View {
        ToolFlow(
            tool: session.tool,
            state: session.state,
            workingTitle: String(localized: "Saving…"),
            workingDetail: session.document.name,
            resultHeadline: isSigning ? String(localized: "Signed and saved") : String(localized: "Changes saved")
        ) {
            editor
        }
        .sheet(item: $session.textRequest) { request in
            TextEntrySheet(request: request) { session.submitText($0) }
        }
        .sheet(item: $session.signaturePad) { kind in
            SignaturePadSheet(kind: kind) { session.signatureDrawn($0) }
        }
        .confirmationDialog(
            session.choiceRequest?.title ?? "",
            isPresented: Binding(get: { session.choiceRequest != nil }, set: { if !$0 { session.choiceRequest = nil } }),
            titleVisibility: .visible
        ) {
            if let request = session.choiceRequest {
                ForEach(request.options, id: \.self) { option in
                    Button(option) { session.choose(option, for: request) }
                }
            }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    session.pendingImage = image.downscaled(maxSide: 2000)
                    session.activeTool = .image
                } else {
                    appState.errorMessage = String(localized: "That photo couldn't be loaded.")
                }
            }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        // The page stops above the bottom bar: under it, the bottom of a page
        // that fits the screen couldn't be reached to sign or write on.
        PageEditorView(session: session)
            .background(Color.groupedBackground)
            .safeAreaInset(edge: .top, spacing: 0) {
                toolStrip
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
                        .disabled(!session.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                    Button("Redo", systemImage: "arrow.uturn.forward") { session.redo() }
                        .disabled(!session.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                    if !isSigning {
                        Menu {
                            Toggle(isOn: $session.flatten) {
                                Label("Flatten on Save", systemImage: "square.3.layers.3d.down.right")
                            }
                            .disabled(session.hasWhiteout)
                        } label: {
                            Label("Options", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .bottomActions {
                contextBar
                Button {
                    appState.saveEdited(session)
                } label: {
                    ToolActionLabel(
                        title: isSigning ? String(localized: "Save Signed PDF") : String(localized: "Save PDF"),
                        tool: session.tool
                    )
                }
                .primaryButtonStyle()
                .disabled(!session.hasChanges)
            }
    }

    /// The tools, in one row that scrolls sideways when it doesn't fit.
    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorTool.tools(for: session.tool)) { tool in
                    ToolChip(tool: tool, isActive: session.activeTool == tool) {
                        pick(tool)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func pick(_ tool: EditorTool) {
        HapticManager.shared.selectionChanged()
        if session.activeTool == tool {
            session.activeTool = nil
            return
        }
        switch tool {
        case .image:
            session.activeTool = .image
            showsPhotoPicker = true
        case .signature, .initials:
            session.activeTool = tool
            let kind: SignatureKind = tool == .signature ? .signature : .initials
            if session.signatures.image(for: kind) == nil {
                session.signaturePad = kind
            }
        default:
            session.activeTool = tool
        }
    }

    /// What can be done right now: act on the selection, or set up the tool.
    @ViewBuilder
    private var contextBar: some View {
        VStack(spacing: 8) {
            if session.selected != nil {
                HStack(spacing: 10) {
                    if session.selectedIsText {
                        Button("Edit", systemImage: "pencil") { session.editSelectedText() }
                    }
                    if session.canResizeSelected {
                        Button("Smaller", systemImage: "minus.magnifyingglass") { session.resizeSelected(by: 1 / 1.2) }
                        Button("Larger", systemImage: "plus.magnifyingglass") { session.resizeSelected(by: 1.2) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { session.deleteSelected() }
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
            } else if let tool = session.activeTool {
                if tool == .signature || tool == .initials {
                    let kind: SignatureKind = tool == .signature ? .signature : .initials
                    if let image = session.signatures.image(for: kind) {
                        HStack(spacing: 12) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 34)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityLabel(kind.title)
                            Button("Draw New") { session.signaturePad = kind }
                                .font(.subheadline)
                        }
                    }
                } else if tool.usesColor {
                    HStack(spacing: 14) {
                        ForEach(EditorColor.allCases) { color in
                            Button {
                                session.color = color
                            } label: {
                                Circle()
                                    .fill(Color(uiColor: color.uiColor))
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        Circle().strokeBorder(.primary, lineWidth: session.color == color ? 2.5 : 0)
                                            .padding(-4)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(session.color == color ? .isSelected : [])
                        }
                        if tool == .draw || tool == .rectangle || tool == .ellipse || tool == .line || tool == .arrow {
                            Divider().frame(height: 22)
                            Picker("Thickness", selection: $session.lineWidth) {
                                Text("Thin").tag(CGFloat(1.5))
                                Text("Medium").tag(CGFloat(3))
                                Text("Thick").tag(CGFloat(6))
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                }
            }

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var caption: String {
        if session.selected == nil {
            if session.activeTool == .whiteout || (session.activeTool == nil && session.hasWhiteout) {
                return String(localized: "White-out covers what is underneath. The covered text stays in the file, so don't use it to hide confidential information.")
            }
            if isSigning && (session.activeTool == .signature || session.activeTool == .initials) {
                return String(localized: "Tap where you want to sign. This is a drawn signature, not a certified digital signature. It is kept on this \(deviceName) only and fixed in place when you save.")
            }
        }
        return session.hint
    }
}

private struct ToolChip: View {
    let tool: EditorTool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(tool.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(minWidth: 58)
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.cardBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - PDF view

/// PDFKit's view with the editor's gestures. Taps and one-finger drags are
/// passed to the session in page coordinates; a drag that the session
/// doesn't want scrolls as usual. What follows the finger is drawn by an
/// `EditorOverlayView` on top, so PDFKit renders a page only when it changed.
struct PageEditorView: UIViewRepresentable {
    let session: EditorSession

    func makeUIView(context: Context) -> EditorPDFView {
        let view = EditorPDFView()
        view.document = session.pdf
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .systemGroupedBackground
        view.overlay.pdfView = view

        let coordinator = context.coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        coordinator.pan = pan
        coordinator.view = view

        session.overlayChanged = { [weak view, weak session] in
            guard let view, let session else { return }
            view.overlay.show(session.overlay)
        }
        view.overlay.show(session.overlay)

        // Scrolling waits until the editor has decided it doesn't want the drag.
        // The overlay follows scrolling and zooming.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            for scrollView in Coordinator.scrollViews(in: view) {
                scrollView.panGestureRecognizer.require(toFail: pan)
                coordinator.observations.append(scrollView.observe(\.contentOffset) { [weak view] _, _ in
                    MainActor.assumeIsolated { view?.overlay.follow() }
                })
            }
        }
        coordinator.observations.append(NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged, object: view, queue: .main
        ) { [weak view] _ in
            MainActor.assumeIsolated { view?.overlay.follow() }
        })
        return view
    }

    func updateUIView(_ view: EditorPDFView, context: Context) {}

    static func dismantleUIView(_ view: EditorPDFView, coordinator: Coordinator) {
        coordinator.session.overlayChanged = nil
        coordinator.observations.removeAll()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let session: EditorSession
        weak var view: PDFView?
        weak var pan: UIPanGestureRecognizer?
        /// Scroll and zoom observers; released with the view.
        var observations: [Any] = []

        init(session: EditorSession) {
            self.session = session
        }

        static func scrollViews(in view: UIView) -> [UIScrollView] {
            view.subviews.flatMap { subview -> [UIScrollView] in
                ((subview as? UIScrollView).map { [$0] } ?? []) + scrollViews(in: subview)
            }
        }

        private func pagePoint(_ location: CGPoint) -> (PDFPage, CGPoint)? {
            guard let view, let page = view.page(for: location, nearest: false) else { return nil }
            return (page, view.convert(location, to: page))
        }

        /// Where the finger came down. A pan is recognized only after the
        /// finger has moved a little; a stroke still starts at the touch.
        private func startLocation(of pan: UIPanGestureRecognizer) -> CGPoint {
            guard let view else { return .zero }
            let location = pan.location(in: view)
            let moved = pan.translation(in: view)
            return CGPoint(x: location.x - moved.x, y: location.y - moved.y)
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view,
                  let (page, point) = pagePoint(recognizer.location(in: view)) else { return }
            session.tap(at: point, on: page)
        }

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            switch recognizer.state {
            case .began:
                guard let (page, start) = pagePoint(startLocation(of: recognizer)) else { return }
                session.dragBegan(at: start, on: page)
                session.dragChanged(to: view.convert(recognizer.location(in: view), to: page))
                activePage = page
            case .changed:
                guard let page = activePage else { return }
                session.dragChanged(to: view.convert(recognizer.location(in: view), to: page))
            case .ended, .cancelled, .failed:
                guard activePage != nil else { return }
                session.dragEnded()
                activePage = nil
            default:
                break
            }
        }

        private var activePage: PDFPage?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, pan === self.pan else { return true }
            guard let (page, point) = pagePoint(startLocation(of: pan)) else { return false }
            return session.canBeginDrag(at: point, on: page)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // The tap must not block PDFKit's own recognizers, nor wait for them.
            recognizer is UITapGestureRecognizer
        }
    }
}

/// PDFKit's view with the editor's overlay on top.
final class EditorPDFView: PDFView {
    let overlay = EditorOverlayView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
        if subviews.last !== overlay { bringSubviewToFront(overlay) }
        overlay.follow()
    }
}

/// Draws the session's overlay above the pages: a shape while it is drawn,
/// something while it is moved, and the selection frame. These are layers
/// over PDFKit's view; changing them never makes PDFKit render a page again.
final class EditorOverlayView: UIView {
    weak var pdfView: PDFView?

    private var content = EditorSession.Overlay()
    private let liveLayer = AnnotationLayer()
    private let frameLayer = CAShapeLayer()
    /// Counts the drags, so a finished one can be cleared a moment later.
    private var liveGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        liveLayer.needsDisplayOnBoundsChange = false
        layer.addSublayer(liveLayer)
        frameLayer.fillColor = nil
        frameLayer.lineWidth = 1.5
        frameLayer.lineDashPattern = [5, 4]
        layer.addSublayer(frameLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        frameLayer.strokeColor = tintColor.cgColor
    }

    func show(_ overlay: EditorSession.Overlay) {
        let ended = content.live != nil && overlay.live == nil
        // When a drag ends, PDFKit draws the page with the result a moment
        // later. Until then the overlay keeps showing it, so nothing flickers.
        if ended {
            liveGeneration += 1
            let generation = liveGeneration
            content.selection = overlay.selection
            follow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.liveGeneration == generation else { return }
                self.content.live = nil
                self.follow()
            }
            return
        }
        if overlay.live != nil { liveGeneration += 1 }
        content = overlay
        follow()
    }

    /// Places the layers for the current scroll position and zoom.
    func follow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let selection = content.selection, let transform = transform(for: selection.page) {
            frameLayer.strokeColor = tintColor.cgColor
            frameLayer.path = CGPath(rect: selection.rect, transform: [transform])
            frameLayer.isHidden = false
        } else {
            frameLayer.isHidden = true
        }

        guard let live = content.live, let transform = transform(for: live.page) else {
            liveLayer.isHidden = true
            liveLayer.annotations = []
            return
        }
        // Room for strokes and arrowheads that reach past an annotation's bounds.
        let pageRect = live.annotations.reduce(CGRect.null) { $0.union($1.bounds) }.insetBy(dx: -12, dy: -12)
        var rect = pageRect.applying(transform).integral
        // When zoomed in far, only what can be seen (and a screen around it) is drawn.
        let visible = bounds.insetBy(dx: -bounds.width, dy: -bounds.height)
        let clipped = rect.width * rect.height > visible.width * visible.height
        if clipped {
            rect = rect.intersection(visible)
        }
        guard !rect.isNull, !rect.isEmpty else {
            liveLayer.isHidden = true
            return
        }
        let unchanged = !clipped && !liveLayer.clipped
            && liveLayer.annotations.count == live.annotations.count
            && zip(liveLayer.annotations, live.annotations).allSatisfy { $0 === $1 }
            && liveLayer.bounds.size == rect.size
            && liveLayer.pageTransform.a == transform.a && liveLayer.pageTransform.b == transform.b
            && liveLayer.pageTransform.c == transform.c && liveLayer.pageTransform.d == transform.d
        liveLayer.isHidden = false
        liveLayer.frame = rect
        // Moved or scrolled without changing: shift the drawing, don't draw it again.
        guard !unchanged else { return }
        liveLayer.contentsScale = traitCollection.displayScale
        liveLayer.annotations = live.annotations
        liveLayer.pageTransform = transform
        liveLayer.origin = rect.origin
        liveLayer.clipped = clipped
        liveLayer.setNeedsDisplay()
    }

    /// Page coordinates (points, y up) to this view's coordinates.
    private func transform(for page: PDFPage) -> CGAffineTransform? {
        guard let pdfView, page.document != nil else { return nil }
        let origin = pdfView.convert(CGPoint.zero, from: page)
        let x = pdfView.convert(CGPoint(x: 100, y: 0), from: page)
        let y = pdfView.convert(CGPoint(x: 0, y: 100), from: page)
        // The overlay covers the PDF view exactly, so its coordinates are the PDF view's.
        return CGAffineTransform(
            a: (x.x - origin.x) / 100, b: (x.y - origin.y) / 100,
            c: (y.x - origin.x) / 100, d: (y.y - origin.y) / 100,
            tx: origin.x, ty: origin.y
        )
    }
}

/// Draws annotations that are not on a page, the way PDFKit draws them on one.
nonisolated final class AnnotationLayer: CALayer {
    var annotations: [PDFAnnotation] = []
    /// Page coordinates to the overlay's coordinates, when the drawing was made.
    var pageTransform: CGAffineTransform = .identity
    /// The layer's place in the overlay when the drawing was made. Moving the
    /// layer later moves the drawing with it.
    var origin: CGPoint = .zero
    /// Only part of the annotations fits the layer.
    var clipped = false

    override func draw(in context: CGContext) {
        context.translateBy(x: -origin.x, y: -origin.y)
        context.concatenate(pageTransform)
        for annotation in annotations {
            annotation.draw(with: .cropBox, in: context)
        }
    }
}

// MARK: - Text entry

private struct TextEntrySheet: View {
    let request: EditorSession.TextRequest
    let onFinish: (String?) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(request: EditorSession.TextRequest, onFinish: @escaping (String?) -> Void) {
        self.request = request
        self.onFinish = onFinish
        _text = State(initialValue: request.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Text", text: $text, axis: request.multiline ? .vertical : .horizontal)
                    .lineLimit(request.multiline ? 2...6 : 1...1)
                    .focused($focused)
                    .submitLabel(request.multiline ? .return : .done)
                    .onSubmit { if !request.multiline { onFinish(text) } }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onFinish(text) }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(240), .medium])
        .interactiveDismissDisabled(false)
    }
}

// MARK: - Signature pad

/// Draw a signature with a finger or Apple Pencil (PencilKit).
struct SignaturePadSheet: View {
    let kind: SignatureKind
    let onFinish: (UIImage?) -> Void

    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ZStack(alignment: .bottom) {
                    SignatureCanvas(drawing: $drawing)
                    VStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.black.opacity(0.18))
                            .frame(height: 1.5)
                            .padding(.horizontal, 22)
                        Text("Sign above the line")
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: 560)
                .frame(height: 200)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
                }

                Text("A drawn signature, not a certified digital signature. It is stored on this \(deviceName) only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.groupedBackground)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                }
            }
            .bottomActions {
                Button {
                    onFinish(SignatureRenderer.image(from: drawing))
                } label: {
                    ActionLabel(title: kind == .signature ? String(localized: "Use Signature") : String(localized: "Use Initials"))
                }
                .primaryButtonStyle()
                .disabled(drawing.strokes.isEmpty)
                Button {
                    drawing = PKDrawing()
                } label: {
                    ActionLabel(title: String(localized: "Clear"))
                }
                .secondaryButtonStyle()
                .disabled(drawing.strokes.isEmpty)
            }
        }
        .presentationDetents([.large])
        .avoidingFoldEdges()
    }
}

private struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The pad is white paper in both appearances; ink must not invert.
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: SignatureRenderer.inkColor, width: 5)
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}

enum SignatureRenderer {
    static let inkColor = UIColor(red: 0.07, green: 0.12, blue: 0.3, alpha: 1)

    /// The strokes on a transparent background, cropped to the ink.
    static func image(from drawing: PKDrawing) -> UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        var image: UIImage?
        // PencilKit adapts ink to the appearance; render it as on white paper.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 3)
        }
        return image
    }
}

extension UIImage {
    /// A copy no larger than `maxSide` on its long side.
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longSide = max(size.width, size.height) * scale
        guard longSide > maxSide else { return self }
        let ratio = maxSide / longSide
        let target = CGSize(width: size.width * scale * ratio, height: size.height * scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
