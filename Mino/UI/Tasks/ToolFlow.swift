//
//  ToolFlow.swift
//  Mino
//
//  The frame every newer tool screen shares: configure → working → result.
//  A tool supplies its configure view; progress, failure and the result
//  screen (Share, Save to Files, Preview, Continue with another tool) are
//  the same everywhere.
//

import SwiftUI

struct ToolFlow<Configure: View, Extras: View>: View {
    let tool: Tool
    let state: TaskState
    /// Shown while working, e.g. "Creating your PDF…".
    let workingTitle: String
    var workingDetail: String = ""
    /// Shown on the result screen, e.g. "PDF created".
    let resultHeadline: String
    @ViewBuilder var configure: () -> Configure
    /// Extra content between the result header and the actions.
    @ViewBuilder var extras: (FileItem) -> Extras

    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            switch state.phase {
            case .configure:
                configure()
            case .working:
                WorkingView(title: workingTitle, detail: workingDetail, progress: state.progress)
                    .background(Color.groupedBackground)
                    .bottomActions {
                        Button {
                            state.cancel()
                        } label: {
                            ActionLabel(title: String(localized: "Cancel"))
                        }
                        .secondaryButtonStyle()
                        .keyboardShortcut(.cancelAction)
                    }
            case .done:
                if let item = state.result {
                    ToolResultView(tool: tool, item: item, headline: resultHeadline) {
                        extras(item)
                    }
                }
            case .failed(let message):
                TaskFailedView(message: message) { state.phase = .configure }
            }
        }
        .navigationTitle(state.phase == .configure ? tool.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(state.phase != .configure)
        .toolbar {
            if sizeClass == .regular && state.phase == .configure {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { appState.closeTask() }
                }
            }
        }
    }
}

extension ToolFlow where Extras == EmptyView {
    init(
        tool: Tool,
        state: TaskState,
        workingTitle: String,
        workingDetail: String = "",
        resultHeadline: String,
        @ViewBuilder configure: @escaping () -> Configure
    ) {
        self.init(
            tool: tool,
            state: state,
            workingTitle: workingTitle,
            workingDetail: workingDetail,
            resultHeadline: resultHeadline,
            configure: configure,
            extras: { _ in EmptyView() }
        )
    }
}

// MARK: - Result

/// The shared result screen.
struct ToolResultView<Extras: View>: View {
    let tool: Tool
    let item: FileItem
    let headline: String
    @ViewBuilder var extras: () -> Extras

    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ResultHeader(headline: headline, detail: "\(item.name) · \(item.summary)")
                extras()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

            Section {
                if item.isImageSet {
                    SaveToPhotosButton(urls: item.urls)
                }
                SaveToFilesButton(urls: item.urls)
                Button {
                    appState.homePath.append(.preview(item))
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                if item.isPDF {
                    Button {
                        appState.showToolPicker(for: item)
                    } label: {
                        Label("Continue with Another Tool", systemImage: "arrow.right")
                    }
                }
            } footer: {
                if AllowanceVisibility.shows(isPro: appState.isPro) {
                    HStack(spacing: 4) {
                        Text("\(appState.usage.remaining) free actions left today.")
                        Button("Go unlimited") { appState.showPaywall(.general) }
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .bottomActions {
            ShareLink(items: item.urls) {
                ActionLabel(title: String(localized: "Share"), systemImage: "square.and.arrow.up")
            }
            .primaryButtonStyle()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { appState.finish(tool) }
            }
        }
    }
}

extension FileItem {
    /// Several image files from PDF to Images.
    var isImageSet: Bool {
        ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
    }
}

// MARK: - Shared pieces

/// The label of a tool's final button. Shows PRO when the tool needs it and
/// the person hasn't unlocked it: the paywall opens here, not earlier.
struct ToolActionLabel: View {
    let title: String
    let tool: Tool
    /// A free tool can still need Pro for an option, such as searchable scans.
    var needsPro = false
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if (tool.access == .pro || needsPro) && !appState.isPro {
                ProBadge()
            }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// The open document with a "Change" button, at the top of a tool screen.
struct DocumentCard: View {
    let document: PDFDocumentInfo
    let change: () -> Void

    var body: some View {
        HStack {
            DocumentRow(document: document, thumbnailWidth: 54)
            Spacer(minLength: 8)
            if document.wasLocked {
                Image(systemName: "lock.open.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Unlocked")
            }
            Button("Change", action: change)
                .buttonStyle(.borderless)
        }
    }
}

/// A small heading above a control in scrolling tool screens.
struct OptionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Shown when a tool's screen is on the path but its session is gone.
struct NoSessionView: View {
    let tool: Tool
    @Environment(AppState.self) private var appState

    var body: some View {
        ContentUnavailableView {
            Label(tool.title, systemImage: tool.systemImage)
        } description: {
            Text(tool.subtitle)
        } actions: {
            Button(tool.input == .pdf ? String(localized: "Choose PDF") : String(localized: "Start")) { appState.open(tool) }
                .secondaryButtonStyle()
        }
    }
}

// MARK: - Page grid

/// Page thumbnails with tap-to-select, shared by Split and PDF to Images.
struct PageSelectionGrid: View {
    let loader: PageThumbnailLoader
    let pageCount: Int
    @Binding var selection: Set<Int>
    var isEnabled = true

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 150), spacing: 12)], spacing: 14) {
            ForEach(1...max(1, pageCount), id: \.self) { page in
                cell(page)
            }
        }
    }

    private func cell(_ page: Int) -> some View {
        let selected = isEnabled && selection.contains(page)
        return Button {
            if selected {
                selection.remove(page)
            } else {
                selection.insert(page)
            }
            HapticManager.shared.selectionChanged()
        } label: {
            VStack(spacing: 6) {
                PageThumbnail(loader: loader, page: page)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: selected ? 3 : 0.5)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                Text(verbatim: "\(page)")
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .hoverEffect(.lift)
        .accessibilityLabel("Page \(page)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
