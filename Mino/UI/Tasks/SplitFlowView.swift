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
        .navigationTitle(session.phase == .configure ? Tool.split.title : "")
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
                        Button(session.selectedPages.count == pageCount ? String(localized: "Deselect All") : String(localized: "Select All")) {
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

                PageSelectionGrid(
                    loader: loader,
                    pageCount: pageCount,
                    selection: $session.selectedPages,
                    isEnabled: session.mode == .choosePages
                )
            }
            .padding(16)
        }
        .background(Color.groupedBackground)
        .bottomActions {
            Button {
                appState.split(session)
            } label: {
                ToolActionLabel(title: actionTitle, tool: .split)
            }
            .primaryButtonStyle()
            .disabled(session.mode == .choosePages && session.selectedPages.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var hint: String {
        switch session.mode {
        case .everyPage:
            return String(localized: "Each page becomes its own PDF.")
        case .choosePages:
            if session.selectedPages.isEmpty { return String(localized: "Tap the pages you want to keep.") }
            return session.selectedPages.count == 1
                ? String(localized: "Selected: page \(session.selectionText)")
                : String(localized: "Selected: pages \(session.selectionText)")
        }
    }

    private var actionTitle: String {
        switch session.mode {
        case .everyPage:
            return String(localized: "Split into \(pageCount) PDFs")
        case .choosePages:
            let count = session.selectedPages.count
            return count == 1 ? String(localized: "Extract 1 Page") : String(localized: "Extract \(count) Pages")
        }
    }

    // MARK: - Working

    private var workingView: some View {
        let everyPage = session.mode == .everyPage
        return WorkingView(
            title: String(localized: "Splitting…"),
            detail: everyPage ? String(localized: "Page \(session.completedPages) of \(pageCount)") : session.document.name,
            progress: everyPage ? Double(session.completedPages) / Double(pageCount) : nil
        )
        .background(Color.groupedBackground)
        .bottomActions {
            if everyPage {
                Button {
                    appState.cancelSplit(session)
                } label: {
                    ActionLabel(title: String(localized: "Cancel"))
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
            headline = String(localized: "\(result.pageCount) pages extracted")
            detail = FileItem(result).name
        } else {
            headline = String(localized: "\(session.results.count) PDFs created")
            detail = String(localized: "From \(session.document.name)")
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
                    Button {
                        appState.showToolPicker(for: FileItem(result))
                    } label: {
                        Label("Continue with Another Tool", systemImage: "arrow.right")
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
                ActionLabel(title: session.results.count > 1 ? String(localized: "Share All") : String(localized: "Share"), systemImage: "square.and.arrow.up")
            }
            .primaryButtonStyle()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { appState.finish(.split) }
            }
        }
    }
}
