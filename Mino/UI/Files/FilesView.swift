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
    /// Nil shows every kind.
    @State private var filter: FileItem.Kind?
    @State private var query = ""
    @State private var pendingDelete: FileItem?

    var body: some View {
        let allFiles = appState.files
        // Only kinds that exist are offered; a filter whose last file was deleted falls back to All.
        let kinds = FileItem.Kind.allCases.filter { kind in allFiles.contains { $0.kind == kind } }
        let activeFilter = filter.flatMap { kinds.contains($0) ? $0 : nil }
        let items = allFiles.filter {
            (activeFilter == nil || $0.kind == activeFilter) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }

        List {
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
                        .swipeActions(edge: .leading) {
                            if item.isPDF {
                                Button {
                                    appState.showToolPicker(for: item)
                                } label: {
                                    Label("Use a Tool", systemImage: "wand.and.stars")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .contextMenu {
                            if item.isPDF {
                                Button {
                                    appState.showToolPicker(for: item)
                                } label: {
                                    Label("Use a Tool", systemImage: "wand.and.stars")
                                }
                            }
                            ShareLink(items: item.urls)
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    let total = items.reduce(Int64(0)) { $0 + $1.size }
                    Text(verbatim: String(localized: "\(items.count) files") + " · " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if kinds.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            Label("All Files", systemImage: "tray.full").tag(FileItem.Kind?.none)
                            ForEach(kinds, id: \.self) { kind in
                                Label(kind.title, systemImage: kind.systemImage).tag(FileItem.Kind?.some(kind))
                            }
                        }
                    } label: {
                        Label(
                            activeFilter?.title ?? String(localized: "Filter"),
                            systemImage: activeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
            }
        }
        .overlay {
            if allFiles.isEmpty {
                ContentUnavailableView {
                    Label("No Files Yet", systemImage: "folder")
                } description: {
                    Text("Everything you make with Mino appears here.")
                } actions: {
                    Button("Open PDF") {
                        appState.selectedTab = .home
                        appState.openPDF()
                    }
                    .secondaryButtonStyle()
                }
            } else if items.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Nothing Here Yet", systemImage: "folder")
                } else {
                    ContentUnavailableView.search(text: query)
                }
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
                QuickLookPreview(urls: item.urls.map(\.standardizedFileURL))
                    .id(item.id)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("File Not Found", systemImage: "doc.questionmark", description: Text("This file may have been deleted."))
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item.isPDF {
                ToolbarItem(placement: .primaryAction) {
                    Button("Use a Tool", systemImage: "wand.and.stars") {
                        appState.showToolPicker(for: item)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(items: item.urls)
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
            DocumentExporter(urls: item.urls) { _ in isExporting = false }
                .ignoresSafeArea()
        }
        .confirmationDialog("Delete “\(item.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { appState.delete(item) }
        } message: {
            Text("This removes the file from Mino. It can't be undone.")
        }
    }
}
