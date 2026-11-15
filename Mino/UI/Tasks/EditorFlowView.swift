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
        PageEditorView(session: session)
            .ignoresSafeArea(edges: .bottom)
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
/// doesn't want scrolls as usual.
struct PageEditorView: UIViewRepresentable {
    let session: EditorSession

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = session.pdf
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .systemGroupedBackground

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        context.coordinator.view = view

        // Scrolling waits until the editor has decided it doesn't want the drag.
        DispatchQueue.main.async {
            Coordinator.scrollViews(in: view).forEach { $0.panGestureRecognizer.require(toFail: pan) }
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Reading the revision makes SwiftUI call this when the pages changed.
        _ = session.revision
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let session: EditorSession
        weak var view: PDFView?
        weak var pan: UIPanGestureRecognizer?

        init(session: EditorSession) {
            self.session = session
        }

        static func scrollViews(in view: UIView) -> [UIScrollView] {
            view.subviews.flatMap { subview -> [UIScrollView] in
                ((subview as? UIScrollView).map { [$0] } ?? []) + scrollViews(in: subview)
            }
        }

        private func pagePoint(_ recognizer: UIGestureRecognizer) -> (PDFPage, CGPoint)? {
            guard let view else { return nil }
            let location = recognizer.location(in: view)
            guard let page = view.page(for: location, nearest: false) else { return nil }
            return (page, view.convert(location, to: page))
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let (page, point) = pagePoint(recognizer) else { return }
            session.tap(at: point, on: page)
        }

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            switch recognizer.state {
            case .began:
                guard let (page, point) = pagePoint(recognizer) else { return }
                session.dragBegan(at: point, on: page)
                activePage = page
            case .changed:
                guard let page = activePage else { return }
                session.dragChanged(to: view.convert(recognizer.location(in: view), to: page))
            case .ended, .cancelled, .failed:
                session.dragEnded()
                activePage = nil
            default:
                break
            }
        }

        private var activePage: PDFPage?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer === pan else { return true }
            guard let (page, point) = pagePoint(recognizer) else { return false }
            return session.canBeginDrag(at: point, on: page)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // The tap must not block PDFKit's own recognizers, nor wait for them.
            recognizer is UITapGestureRecognizer
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
