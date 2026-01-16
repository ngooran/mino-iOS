//
//  GeneratedFilesView.swift
//  Mino
//
//  View showing all generated files organized by category
//

import SwiftUI

struct GeneratedFilesView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedCategory: FileCategory = .compressed
    @State private var fileToPreview: PreviewFile?
    @State private var showingDeleteAllConfirm = false

    enum FileCategory: String, CaseIterable {
        case compressed = "Compressed"
        case merged = "Merged"
        case split = "Split"

        var icon: String {
            switch self {
            case .compressed: return "arrow.down.doc.fill"
            case .merged: return "doc.on.doc.fill"
            case .split: return "scissors"
            }
        }

        var color: Color {
            switch self {
            case .compressed: return Color.minoSuccess
            case .merged: return Color.minoAccent
            case .split: return .orange
            }
        }
    }

    /// Whether the current category has files
    private var currentCategoryHasFiles: Bool {
        switch selectedCategory {
        case .compressed:
            return !appState.compressionService.recentResults.isEmpty
        case .merged:
            return !appState.mergeService.recentResults.isEmpty
        case .split:
            return !appState.splitService.recentResults.isEmpty
        }
    }

    /// File count for current category
    private var currentCategoryFileCount: Int {
        switch selectedCategory {
        case .compressed:
            return appState.compressionService.recentResults.count
        case .merged:
            return appState.mergeService.recentResults.count
        case .split:
            return appState.splitService.recentResults.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented category picker
            segmentedPicker
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // File list
            fileList
        }
        .minoHeroBackground()
        .minoToolbarStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if currentCategoryHasFiles {
                    Button(role: .destructive) {
                        showingDeleteAllConfirm = true
                    } label: {
                        Text("Delete All")
                            .font(.subheadline)
                            .foregroundStyle(Color.minoError)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete All \(selectedCategory.rawValue) Files",
            isPresented: $showingDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(currentCategoryFileCount) Files", role: .destructive) {
                withAnimation {
                    deleteAllInCurrentCategory()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(selectedCategory.rawValue.lowercased()) files. This action cannot be undone.")
        }
        .fullScreenCover(item: $fileToPreview) { file in
            PDFViewerView(documentURL: file.url)
        }
    }

    // MARK: - Delete All

    private func deleteAllInCurrentCategory() {
        switch selectedCategory {
        case .compressed:
            appState.compressionService.clearAllResults()
        case .merged:
            appState.mergeService.clearAllResults()
        case .split:
            appState.splitService.clearAllResults()
        }
    }

    // MARK: - Segmented Picker

    private var segmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(FileCategory.allCases, id: \.self) { category in
                let isSelected = selectedCategory == category

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(category.color)
                                    .matchedGeometryEffect(id: "segment", in: segmentNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    @Namespace private var segmentNamespace

    // MARK: - File List

    private var fileList: some View {
        Group {
            switch selectedCategory {
            case .compressed:
                compressedFilesList
            case .merged:
                mergedFilesList
            case .split:
                splitFilesList
            }
        }
    }

    private var compressedFilesList: some View {
        let results = appState.compressionService.recentResults
        return Group {
            if results.isEmpty {
                emptyState(for: .compressed)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { result in
                            FileCard(
                                icon: "arrow.down.doc.fill",
                                iconColor: Color.minoSuccess,
                                title: result.outputURL.deletingPathExtension().lastPathComponent,
                                subtitle: result.formattedCompressedSize,
                                badge: "-\(result.formattedReduction)",
                                badgeColor: Color.minoSuccess,
                                url: result.outputURL,
                                onTap: { openViewer(url: result.outputURL) },
                                onDelete: { appState.compressionService.deleteResult(result) }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private var mergedFilesList: some View {
        let results = appState.mergeService.recentResults
        return Group {
            if results.isEmpty {
                emptyState(for: .merged)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { result in
                            FileCard(
                                icon: "doc.on.doc.fill",
                                iconColor: Color.minoAccent,
                                title: result.fileName,
                                subtitle: "\(result.formattedSize) • \(result.totalPages) pages",
                                badge: nil,
                                badgeColor: nil,
                                url: result.outputURL,
                                onTap: { openViewer(url: result.outputURL) },
                                onDelete: { appState.mergeService.deleteResult(result) }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private var splitFilesList: some View {
        let results = appState.splitService.recentResults
        return Group {
            if results.isEmpty {
                emptyState(for: .split)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { result in
                            FileCard(
                                icon: "scissors",
                                iconColor: .orange,
                                title: result.fileName,
                                subtitle: "\(result.formattedSize) • \(result.pageCount == 1 ? "Page" : "Pages") \(result.pageRange)",
                                badge: nil,
                                badgeColor: nil,
                                url: result.outputURL,
                                onTap: { openViewer(url: result.outputURL) },
                                onDelete: { appState.splitService.deleteResult(result) }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(for category: FileCategory) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(category.color.opacity(0.1))
                    .frame(width: 88, height: 88)

                Image(systemName: category.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(category.color.opacity(0.4))
            }

            VStack(spacing: 8) {
                Text("No \(category.rawValue) Files")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(emptySubtitle(for: category))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func emptySubtitle(for category: FileCategory) -> String {
        switch category {
        case .compressed:
            return "Compress a PDF to see it here"
        case .merged:
            return "Merge PDFs to see them here"
        case .split:
            return "Split a PDF to see results here"
        }
    }

    // MARK: - Helpers

    private func openViewer(url: URL) {
        fileToPreview = PreviewFile(url: url)
    }
}

// MARK: - Preview File (for fullScreenCover item binding)

struct PreviewFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - File Card

struct FileCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String?
    let badgeColor: Color?
    let url: URL
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingExportPicker = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(iconColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Badge (if any)
                if let badge = badge, let badgeColor = badgeColor {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(badgeColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Actions menu
                Menu {
                    Button {
                        onTap()
                    } label: {
                        Label("View", systemImage: "eye")
                    }

                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingExportPicker = true
                    } label: {
                        Label("Save to Files", systemImage: "folder")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            .padding(14)
            .background(Color.minoCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FileCardButtonStyle())
        .sheet(isPresented: $showingExportPicker) {
            DocumentExporter(url: url) { _ in
                showingExportPicker = false
            }
        }
        .confirmationDialog("Delete File", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this file.")
        }
    }
}

// MARK: - File Card Button Style

struct FileCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        GeneratedFilesView()
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
