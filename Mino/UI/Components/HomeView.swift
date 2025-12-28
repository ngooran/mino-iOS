//
//  HomeView.swift
//  Mino
//
//  Main home screen with import options
//

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var showingClearAllConfirmation = false

    var body: some View {
        @Bindable var state = appState

        Group {
            if appState.compressionService.recentResults.isEmpty && appState.importedDocuments.isEmpty {
                // Empty state - centered with character
                emptyStateView
            } else {
                // Has content - scrollable list with FAB
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Recent documents
                            if !appState.importedDocuments.isEmpty {
                                recentDocumentsSection
                            }

                            // Compressed files
                            if !appState.compressionService.recentResults.isEmpty {
                                compressedFilesSection
                            }

                            Spacer(minLength: 100)
                        }
                        .padding()
                    }

                    // Floating Action Button
                    fabButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Compress PDFs")
        .navigationBarTitleDisplayMode(.inline)
        .onDrop(of: [.pdf], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .alert(
            "Clear All Compressed Files",
            isPresented: $showingClearAllConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                appState.compressionService.clearAllResults()
            }
        } message: {
            Text("This will permanently delete all \(appState.compressionService.recentResults.count) compressed PDF files. This action cannot be undone.")
        }
    }

    // MARK: - Views

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "doc.zipper")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                }

                // Title and description
                headerSection

                // CTA Button
                importButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Compress PDFs")
                .font(.title2.bold())

            Text("Reduce file size while maintaining quality.\nAll processing happens on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    private var importButton: some View {
        @Bindable var state = appState

        return Button {
            state.showingDocumentPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Select PDF")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var fabButton: some View {
        @Bindable var state = appState

        return Button {
            state.showingDocumentPicker = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var recentDocumentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Documents")
                    .font(.headline)
                Spacer()
                if appState.importedDocuments.count > 3 {
                    Button("See All") {
                        // Could navigate to full list
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.importedDocuments.prefix(5)) { document in
                        DocumentCard(document: document)
                            .onTapGesture {
                                appState.startCompression(for: document)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var compressedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compressed Files")
                    .font(.headline)

                Spacer()

                Button("Clear All") {
                    showingClearAllConfirmation = true
                }
                .font(.subheadline)
                .foregroundStyle(.red)
            }
            .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(appState.compressionService.recentResults) { result in
                    CompressedFileCard(result: result)
                        .onTapGesture {
                            appState.showResults(result)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.compressionService.deleteResult(result)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            ShareLink(item: result.outputURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                }
                .onDelete { indexSet in
                    let resultsToDelete = indexSet.map { appState.compressionService.recentResults[$0] }
                    for result in resultsToDelete {
                        appState.compressionService.deleteResult(result)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
            guard let url = url else { return }

            Task { @MainActor in
                do {
                    let document = try await appState.documentImporter.importDocument(from: url)
                    appState.addImportedDocument(document)
                    appState.startCompression(for: document)
                } catch {
                    appState.showError(error)
                }
            }
        }
    }
}

// MARK: - Document Card

struct DocumentCard: View {
    let document: PDFDocumentInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)

            Text(document.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(document.shortDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 130, height: 130, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Compressed File Card

struct CompressedFileCard: View {
    let result: CompressionResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.title2)
                .foregroundStyle(Color.minoAccent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.outputFileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(result.formattedOriginalSize)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(result.formattedCompressedSize)
                        .foregroundStyle(Color.minoSuccess)
                }
                .font(.caption)
            }

            Spacer()

            Text("-\(result.formattedReduction)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.minoSuccess)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(AppState())
}
