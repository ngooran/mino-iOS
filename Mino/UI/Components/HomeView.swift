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

    private var hasRecentActivity: Bool {
        !appState.compressionService.recentResults.isEmpty
    }

    var body: some View {
        @Bindable var state = appState

        Group {
            if hasRecentActivity {
                // Has history - scrollable with hero at top
                ScrollView {
                    VStack(spacing: 20) {
                        heroCard
                        compressedFilesSection
                        Spacer(minLength: 100)
                    }
                    .padding()
                }
            } else {
                // No history - center the hero
                VStack {
                    Spacer()
                    heroCard
                        .padding()
                    Spacer()
                }
            }
        }
        .background(Color.minoBackground)
        .minoToolbarStyle()
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

    // MARK: - Hero Card

    private var heroCard: some View {
        @Bindable var state = appState

        return VStack(spacing: 20) {
            // Icon in circle
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }

            // Title and subtitle
            VStack(spacing: 8) {
                Text("Reduce PDF Size")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                Text("Make your documents easier to share\nwithout losing quality.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
            }

            // CTA Button
            Button {
                state.showingDocumentPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.body.weight(.semibold))
                    Text("Select PDF File")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .minoGlassAccentButton()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Image("MinoHeroImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                // Dark overlay for text readability
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.5),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.minoCardBorder, lineWidth: 1)
        )
    }

    // MARK: - Compressed Files Section

    private var compressedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)

                Spacer()

                Button("Clear All") {
                    showingClearAllConfirmation = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.minoAccent)
            }

            // List items
            VStack(spacing: 10) {
                ForEach(appState.compressionService.recentResults) { result in
                    CompressedFileCard(result: result) {
                        appState.compressionService.deleteResult(result)
                    }
                    .onTapGesture {
                        appState.showResults(result)
                    }
                }
            }
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
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.minoAccent.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "doc.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.minoAccent)
            }

            Text(document.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(document.shortDescription)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .frame(width: 130, height: 120, alignment: .topLeading)
        .minoGlass(in: 12)
    }
}

// MARK: - Compressed File Card

struct CompressedFileCard: View {
    let result: CompressionResult
    var onDelete: (() -> Void)? = nil

    @State private var showingExportPicker = false

    var body: some View {
        HStack(spacing: 14) {
            // PDF Icon in rounded square
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.minoAccent.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.minoAccent)
            }

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.outputFileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(result.formattedOriginalSize)
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                    Text(result.formattedCompressedSize)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.caption)
            }

            Spacer()

            // Reduction badge (pill)
            Text("-\(result.formattedReduction)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.minoSuccess)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.minoSuccess.opacity(0.15))
                .clipShape(Capsule())

            // Menu button
            Menu {
                ShareLink(item: result.outputURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingExportPicker = true
                } label: {
                    Label("Save to Files", systemImage: "folder")
                }

                Divider()

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(14)
        .minoGlass(in: 14)
        .contentShape(Rectangle())
        .sheet(isPresented: $showingExportPicker) {
            DocumentExporter(url: result.outputURL) { _ in
                showingExportPicker = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
