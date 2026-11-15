//
//  OrganizeFlowView.swift
//  Mino
//
//  Page grid → select → rotate, move, duplicate, delete, insert → Save.
//

import SwiftUI

struct OrganizeFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.organizeSession {
            OrganizeContent(session: session)
                .id(session.document.id)
        } else {
            NoSessionView(tool: .organize)
        }
    }
}

private struct OrganizeContent: View {
    @Bindable var session: OrganizeSession
    @Environment(AppState.self) private var appState
    /// One thumbnail loader per PDF that contributes pages.
    @State private var loaders: [URL: PageThumbnailLoader] = [:]
    @State private var showsCamera = false

    var body: some View {
        ToolFlow(
            tool: .organize,
            state: session.state,
            workingTitle: String(localized: "Saving…"),
            workingDetail: session.document.name,
            resultHeadline: String(localized: "Pages updated")
        ) {
            configureView
        }
    }

    private var hasSelection: Bool { !session.selection.isEmpty }

    private var configureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                actionBar

                HStack(alignment: .firstTextBaseline) {
                    Text(hasSelection
                         ? String(localized: "\(session.selection.count) selected")
                         : String(localized: "Select pages to rotate, move, duplicate or delete. Drag a page to move it."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if hasSelection {
                        Button("Deselect") { session.selection.removeAll() }
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 150), spacing: 12)], spacing: 14) {
                    ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
                        pageCell(page, number: index + 1)
                            .draggable(page.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                                withAnimation { session.move(dragged, to: page.id) }
                                return true
                            }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.groupedBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        withAnimation { session.insertBlankPage() }
                    } label: {
                        Label("Blank Page", systemImage: "doc")
                    }
                    Button {
                        appState.addPagesToOrganize()
                    } label: {
                        Label("Pages from Another PDF", systemImage: "doc.on.doc")
                    }
                    if Tool.scan.isAvailable && DocumentCamera.isSupported {
                        Button {
                            showsCamera = true
                        } label: {
                            Label("Scan Pages", systemImage: "doc.viewfinder")
                        }
                    }
                } label: {
                    Label("Insert", systemImage: "plus")
                }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            DocumentCamera { images in
                showsCamera = false
                Task { await appState.insertScannedPages(images, into: session) }
            }
            .ignoresSafeArea()
        }
        .bottomActions {
            Button {
                appState.saveOrganized(session)
            } label: {
                ToolActionLabel(title: String(localized: "Save Changes"), tool: .organize)
            }
            .primaryButtonStyle()
            .disabled(!session.hasChanges)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            ActionBarButton(title: String(localized: "Rotate"), systemImage: "rotate.right") {
                withAnimation { session.rotateSelection() }
            }
            ActionBarButton(title: String(localized: "Earlier"), systemImage: "arrow.left") {
                withAnimation { session.moveSelection(by: -1) }
            }
            ActionBarButton(title: String(localized: "Later"), systemImage: "arrow.right") {
                withAnimation { session.moveSelection(by: 1) }
            }
            ActionBarButton(title: String(localized: "Duplicate"), systemImage: "plus.square.on.square") {
                withAnimation { session.duplicateSelection() }
            }
            ActionBarButton(title: String(localized: "Delete"), systemImage: "trash", role: .destructive) {
                withAnimation { session.deleteSelection() }
            }
            .disabled(session.selection.count >= session.pages.count)
        }
        .disabled(!hasSelection)
    }

    private func pageCell(_ page: OrganizedPage, number: Int) -> some View {
        let selected = session.selection.contains(page.id)
        return Button {
            session.toggle(page)
            HapticManager.shared.selectionChanged()
        } label: {
            VStack(spacing: 6) {
                OrganizeThumbnail(page: page, loader: loader(for: page))
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(4)
                        }
                    }
                    .padding(4)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.16) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
                    }
                Text(verbatim: "\(number)")
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("Page \(number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func loader(for page: OrganizedPage) -> PageThumbnailLoader? {
        let url: URL
        switch page.source {
        case .original: url = session.document.url
        case .external(let external, _): url = external
        case .blank: return nil
        }
        if let existing = loaders[url] { return existing }
        let loader = PageThumbnailLoader(url: url)
        // Deferred: state can't change while the view is being built.
        Task { @MainActor in loaders[url] = loader }
        return loader
    }
}

private struct ActionBarButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 2)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .hoverEffect(.highlight)
    }
}

/// A page in the Organize grid, drawn with its added rotation. The cell is
/// square, so a page fits whichever way it is turned.
private struct OrganizeThumbnail: View {
    let page: OrganizedPage
    let loader: PageThumbnailLoader?

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    switch page.source {
                    case .blank(let width, let height):
                        Color.white
                            .aspectRatio(width / max(1, height), contentMode: .fit)
                    case .original, .external:
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Color.white
                                .aspectRatio(0.77, contentMode: .fit)
                                .overlay { ProgressView().controlSize(.small).tint(.gray) }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .rotationEffect(.degrees(Double(page.rotation)))
            }
            .task(id: sourceKey) {
                guard let loader else { return }
                switch page.source {
                case .original(let index), .external(_, let index):
                    image = await loader.thumbnail(page: index + 1, size: CGSize(width: 240, height: 312))
                case .blank:
                    break
                }
            }
    }

    private var sourceKey: String {
        switch page.source {
        case .original(let index): return "o\(index)-\(loader == nil)"
        case .external(let url, let index): return "\(url.path)-\(index)-\(loader == nil)"
        case .blank: return "blank"
        }
    }
}
