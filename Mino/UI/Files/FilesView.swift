//
//  FilesView.swift
//  Mino
//
//  Every generated file in one searchable list, with a type filter.
//

import SwiftUI

struct FilesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var pendingDelete: FileItem?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case compressed = "Compressed"
        case merged = "Merged"
        case split = "Split"

        var id: String { rawValue }

        func includes(_ item: FileItem) -> Bool {
            switch self {
            case .all: return true
            case .compressed: return item.kind == .compressed
            case .merged: return item.kind == .merged
            case .split: return item.kind == .split
            }
        }
    }

    var body: some View {
        let allFiles = appState.files
        let items = allFiles.filter {
            filter.includes($0) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }

        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        Button {
                            appState.show(.preview(item), in: .files)
                        } label: {
                            FileRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(isSelected(item) ? Color.accentColor.opacity(0.15) : nil)
                        .swipeActions {
                            Button(role: .destructive) {
                                appState.delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            ShareLink(item: item.url)
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    let total = items.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(items.count) \(items.count == 1 ? "file" : "files") · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if allFiles.isEmpty {
                ContentUnavailableView {
                    Label("No Files Yet", systemImage: "folder")
                } description: {
                    Text("PDFs you compress, merge or split appear here.")
                } actions: {
                    Button("Compress a PDF") {
                        appState.selectedTab = .home
                        appState.chooseFilesToCompress()
                    }
                    .secondaryButtonStyle()
                }
            } else if items.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { appState.delete(pendingDelete) }
            }
        }
    }

    private func isSelected(_ item: FileItem) -> Bool {
        guard sizeClass == .regular else { return false }
        if let first = appState.filesPath.first { return first == .preview(item) }
        return appState.files.first == item
    }
}

// MARK: - Preview

struct FilePreviewView: View {
    let item: FileItem
    @Environment(AppState.self) private var appState
    @State private var isExporting = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if FileManager.default.fileExists(atPath: item.url.path) {
                QuickLookPreview(url: item.url.standardizedFileURL)
                    .id(item.id)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("File Not Found", systemImage: "doc.questionmark", description: Text("This file may have been deleted."))
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: item.url)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isExporting = true
                    } label: {
                        Label("Save to Files", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isExporting) {
            DocumentExporter(urls: [item.url]) { _ in isExporting = false }
                .ignoresSafeArea()
        }
        .confirmationDialog("Delete “\(item.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { appState.delete(item) }
        } message: {
            Text("This removes the file from Mino. It can't be undone.")
        }
    }
}
