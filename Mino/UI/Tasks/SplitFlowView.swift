//
//  SplitFlowView.swift
//  Mino
//
//  Tap page thumbnails (or choose every page) → split → result.
//

import SwiftUI

struct SplitFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.splitSession {
            SplitContent(session: session)
                .id(session.document.id)
        } else {
            ContentUnavailableView("No PDF Selected", systemImage: "scissors", description: Text("Open Split on Home and choose a PDF."))
        }
    }
}

private struct SplitContent: View {
    @Bindable var session: SplitSession
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var loader: PageThumbnailLoader

    init(session: SplitSession) {
        self.session = session
        _loader = State(initialValue: PageThumbnailLoader(url: session.document.url))
    }

    private var pageCount: Int { max(1, session.document.pageCount) }

    var body: some View {
        Group {
            switch session.phase {
            case .configure:
                configureView
            case .working:
                workingView
            case .done:
                resultView
            case .failed(let message):
                TaskFailedView(message: message) { session.phase = .configure }
            }
        }
        .navigationTitle(session.phase == .configure ? "Split" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(session.phase != .configure)
        .toolbar {
            if sizeClass == .regular && session.phase == .configure {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { appState.closeTask() }
                }
            }
        }
    }

    // MARK: - Configure

    private var configureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    DocumentRow(document: session.document, thumbnailWidth: 54)
                    Spacer(minLength: 8)
                    Button("Change") { appState.chooseFileToSplit() }
                }
                .cardStyle()

                Picker("Split mode", selection: $session.mode) {
                    Text("Choose Pages").tag(SplitSession.Mode.choosePages)
                    Text("Every Page").tag(SplitSession.Mode.everyPage)
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline) {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    Spacer()
                    if session.mode == .choosePages {
                        Button(session.selectedPages.count == pageCount ? "Deselect All" : "Select All") {
                            if session.selectedPages.count == pageCount {
                                session.selectedPages.removeAll()
                            } else {
                                session.selectedPages = Set(1...pageCount)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 150), spacing: 12)], spacing: 14) {
                    ForEach(1...pageCount, id: \.self) { page in
                        pageCell(page)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.groupedBackground)
        .bottomActions {
            Button {
                appState.split(session)
            } label: {
                ActionLabel(title: actionTitle)
            }
            .primaryButtonStyle()
            .disabled(session.mode == .choosePages && session.selectedPages.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var hint: String {
        switch session.mode {
        case .everyPage:
            return "Each page becomes its own PDF."
        case .choosePages:
            if session.selectedPages.isEmpty { return "Tap the pages you want to keep." }
            let noun = session.selectedPages.count == 1 ? "page" : "pages"
            return "Selected: \(noun) \(session.selectionText)"
        }
    }

    private var actionTitle: String {
        switch session.mode {
        case .everyPage:
            return "Split into \(pageCount) PDFs"
        case .choosePages:
            let count = session.selectedPages.count
            return count == 1 ? "Extract 1 Page" : "Extract \(count) Pages"
        }
    }

    private func pageCell(_ page: Int) -> some View {
        let selected = session.mode == .choosePages && session.selectedPages.contains(page)
        return Button {
            if selected {
                session.selectedPages.remove(page)
            } else {
                session.selectedPages.insert(page)
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
                Text("\(page)")
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.mode == .everyPage)
        .hoverEffect(.lift)
        .accessibilityLabel("Page \(page)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Working

    private var workingView: some View {
        let everyPage = session.mode == .everyPage
        return WorkingView(
            title: "Splitting…",
            detail: everyPage ? "Page \(session.completedPages) of \(pageCount)" : session.document.name,
            progress: everyPage ? Double(session.completedPages) / Double(pageCount) : nil
        )
        .background(Color.groupedBackground)
        .bottomActions {
            if everyPage {
                Button {
                    appState.cancelSplit(session)
                } label: {
                    ActionLabel(title: "Cancel")
                }
                .secondaryButtonStyle()
            }
        }
    }

    // MARK: - Result

    private var resultView: some View {
        let urls = session.results.map(\.outputURL)
        let headline: String
        let detail: String
        if session.results.count == 1, let result = session.results.first {
            headline = result.pageCount == 1 ? "1 page extracted" : "\(result.pageCount) pages extracted"
            detail = FileItem(result).name
        } else {
            headline = "\(session.results.count) PDFs created"
            detail = "From \(session.document.name)"
        }

        return List {
            Section {
                ResultHeader(headline: headline, detail: detail)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                SaveToFilesButton(urls: urls)
                if session.results.count == 1, let result = session.results.first {
                    Button {
                        appState.homePath.append(.preview(FileItem(result)))
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                }
            }

            if session.results.count > 1 {
                Section("Files") {
                    ForEach(session.results) { result in
                        let item = FileItem(result)
                        Button {
                            appState.homePath.append(.preview(item))
                        } label: {
                            FileRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .bottomActions {
            ShareLink(items: urls) {
                ActionLabel(title: session.results.count > 1 ? "Share All" : "Share", systemImage: "square.and.arrow.up")
            }
            .primaryButtonStyle()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    appState.splitSession = nil
                    appState.closeTask()
                }
            }
        }
    }
}
