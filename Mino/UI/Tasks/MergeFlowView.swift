//
//  MergeFlowView.swift
//  Mino
//
//  Reorderable list of PDFs → merge → result.
//

import SwiftUI

struct MergeFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.mergeSession {
            MergeContent(session: session)
        } else {
            ContentUnavailableView("Nothing to Merge", systemImage: "doc.on.doc", description: Text("Open Merge on Home to combine PDFs."))
        }
    }
}

private struct MergeContent: View {
    @Bindable var session: MergeSession
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            switch session.phase {
            case .configure:
                configureView
            case .working:
                WorkingView(title: "Merging…", detail: "\(session.documents.count) PDFs", progress: appState.mergeProgress)
                    .background(Color.groupedBackground)
            case .done:
                resultView
            case .failed(let message):
                TaskFailedView(message: message) { session.phase = .configure }
            }
        }
        .navigationTitle(session.phase == .configure ? "Merge" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(session.phase != .configure)
        .toolbar {
            if session.phase == .configure {
                if sizeClass == .regular {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { appState.closeTask() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add PDFs", systemImage: "plus") { appState.addFilesToMerge() }
                }
            }
        }
    }

    // MARK: - Configure

    @ViewBuilder
    private var configureView: some View {
        if session.documents.isEmpty {
            ContentUnavailableView {
                Label("Add PDFs to Merge", systemImage: "doc.on.doc")
            } description: {
                Text("Choose two or more PDFs. You can change their order before merging.")
            } actions: {
                Button("Choose PDFs") { appState.addFilesToMerge() }
                    .secondaryButtonStyle()
            }
        } else {
            List {
                Section {
                    ForEach(session.documents) { document in
                        DocumentRow(document: document)
                    }
                    .onMove { session.documents.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { session.documents.remove(atOffsets: $0) }
                } header: {
                    Text("Drag to set the order")
                } footer: {
                    Text("\(session.documents.count) PDFs · \(session.totalPages) pages · about \(ByteCountFormatter.string(fromByteCount: session.totalSize, countStyle: .file))")
                }

                Section {
                    Button {
                        appState.addFilesToMerge()
                    } label: {
                        Label("Add PDFs", systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .bottomActions {
                Button {
                    appState.merge(session)
                } label: {
                    ActionLabel(title: session.documents.count < 2 ? "Add at Least 2 PDFs" : "Merge \(session.documents.count) PDFs")
                }
                .primaryButtonStyle()
                .disabled(session.documents.count < 2)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultView: some View {
        if let result = session.result {
            let item = FileItem(result)
            List {
                Section {
                    ResultHeader(headline: "PDFs merged", detail: item.name)
                    VStack(spacing: 10) {
                        LabeledContent("Files combined", value: "\(result.sourceCount)")
                        LabeledContent("Pages", value: "\(result.totalPages)")
                        LabeledContent("Size", value: result.formattedSize)
                    }
                    .font(.subheadline)
                    .cardStyle()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)

                Section {
                    SaveToFilesButton(urls: [result.outputURL])
                    Button {
                        appState.homePath.append(.preview(item))
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .bottomActions {
                ShareLink(item: result.outputURL) {
                    ActionLabel(title: "Share", systemImage: "square.and.arrow.up")
                }
                .primaryButtonStyle()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        appState.mergeSession = nil
                        appState.closeTask()
                    }
                }
            }
        }
    }
}
