//
//  ToolsView.swift
//  Mino
//
//  Main tools tab with compress, merge, and split options
//

import SwiftUI

struct ToolsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Tool cards
                VStack(spacing: 16) {
                    compressCard
                    mergeCard
                    splitCard
                }

                Spacer(minLength: 100)
            }
            .padding()
        }
        .minoHeroBackground()
        .minoToolbarStyle()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.minoAccent.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "doc.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.minoAccent)
            }

            VStack(spacing: 4) {
                Text("PDF Tools")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Compress, merge, and split your PDFs")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Compress Card

    @State private var showingCompressPicker = false

    private var compressCard: some View {
        Button {
            showingCompressPicker = true
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.minoAccent.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.minoAccent)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compress PDF")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Select one or multiple PDFs to compress")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
            .minoGlass(in: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingCompressPicker) {
            MultiDocumentPicker { urls in
                Task {
                    await handleCompressSelection(urls: urls)
                }
            } onCancel: {
                showingCompressPicker = false
            }
        }
    }

    private func handleCompressSelection(urls: [URL]) async {
        showingCompressPicker = false

        var documents: [PDFDocumentInfo] = []
        for url in urls {
            if let doc = try? await appState.documentImporter.importDocument(from: url) {
                documents.append(doc)
            }
        }

        guard !documents.isEmpty else { return }

        // Use unified compression flow for both single and multiple files
        appState.startCompressionForDocuments(documents)
    }

    // MARK: - Merge Card

    private var mergeCard: some View {
        @Bindable var state = appState

        return Button {
            state.showingMergeView = true
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.minoAccent.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.minoAccent)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Merge PDFs")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Combine multiple PDF files into one document")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
            .minoGlass(in: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Split Card

    private var splitCard: some View {
        @Bindable var state = appState

        return Button {
            state.showingDocumentPickerForSplit = true
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.minoSuccess.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "scissors")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.minoSuccess)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Split PDF")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Extract pages or split into individual files")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
            .minoGlass(in: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ToolsView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
