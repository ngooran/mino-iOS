//
//  MergeView.swift
//  Mino
//
//  View for merging multiple PDFs into one
//

import SwiftUI

struct MergeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDocuments: [PDFDocumentInfo] = []
    @State private var outputName: String = ""
    @State private var showingFilePicker = false
    @State private var isMerging = false
    @State private var mergeResult: MergeResult?
    @State private var showingResult = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedDocuments.isEmpty {
                    emptyState
                } else {
                    documentList
                }

                Spacer()

                bottomBar
            }
            .background(Color.minoBackground)
            .navigationTitle("Merge PDFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .minoToolbarStyle()
            .sheet(isPresented: $showingFilePicker) {
                MultiDocumentPicker { urls in
                    Task {
                        await importDocuments(urls)
                    }
                    showingFilePicker = false
                } onCancel: {
                    showingFilePicker = false
                }
            }
            .sheet(isPresented: $showingResult) {
                if let result = mergeResult {
                    MergeResultView(result: result) {
                        showingResult = false
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .overlay {
                if isMerging {
                    MergeOverlay(job: appState.mergeService.currentJob)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.minoAccent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.minoAccent)
            }

            VStack(spacing: 8) {
                Text("No PDFs Selected")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Add at least 2 PDF files to merge them into a single document.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showingFilePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add PDF Files")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .minoGlassAccentButton()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Document List

    private var documentList: some View {
        List {
            Section {
                ForEach(selectedDocuments) { document in
                    MergeDocumentRow(document: document)
                }
                .onMove { from, to in
                    selectedDocuments.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { indexSet in
                    selectedDocuments.remove(atOffsets: indexSet)
                }
            } header: {
                HStack {
                    Text("\(selectedDocuments.count) FILES")
                    Spacer()
                    Text("Drag to reorder")
                        .textCase(nil)
                        .font(.caption)
                }
            } footer: {
                Text("Files will be merged in the order shown above.")
                    .font(.caption)
            }

            Section {
                Button {
                    showingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.minoAccent)
                        Text("Add More Files")
                            .foregroundStyle(Color.minoAccent)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Output name field
            HStack {
                Text("Output Name")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                TextField("merged", text: $outputName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            .padding(.horizontal)

            // Summary
            if selectedDocuments.count >= 2 {
                HStack {
                    Text("Total: \(totalPages) pages")
                    Spacer()
                    Text(totalSize)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal)
            }

            // Merge button
            Button {
                Task {
                    await performMerge()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Merge \(selectedDocuments.count) PDFs")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .minoGlassAccentButton()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedDocuments.count < 2 || isMerging)
            .opacity(selectedDocuments.count < 2 ? 0.5 : 1)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.minoCardBackground)
    }

    // MARK: - Computed Properties

    private var totalPages: Int {
        selectedDocuments.reduce(0) { $0 + $1.pageCount }
    }

    private var totalSize: String {
        let bytes = selectedDocuments.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Actions

    private func importDocuments(_ urls: [URL]) async {
        for url in urls {
            do {
                let document = try await appState.documentImporter.importDocument(from: url)
                if !selectedDocuments.contains(where: { $0.id == document.id }) {
                    selectedDocuments.append(document)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Set default output name if empty
        if outputName.isEmpty && !selectedDocuments.isEmpty {
            outputName = PDFMerger.suggestedOutputName(from: selectedDocuments)
        }
    }

    private func performMerge() async {
        guard selectedDocuments.count >= 2 else { return }

        isMerging = true
        HapticManager.shared.compressionStart()

        do {
            let name = outputName.isEmpty ? "merged" : outputName
            let result = try await appState.mergeService.merge(
                documents: selectedDocuments,
                outputName: name
            )
            mergeResult = result
            isMerging = false
            HapticManager.shared.compressionComplete()
            showingResult = true
        } catch {
            isMerging = false
            HapticManager.shared.error()
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Merge Document Row

struct MergeDocumentRow: View {
    let document: PDFDocumentInfo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.minoAccent.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "doc.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.minoAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(document.pageCount) pages • \(document.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .listRowBackground(Color.minoCardBackground)
    }
}

// MARK: - Merge Overlay

struct MergeOverlay: View {
    let job: MergeJob?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.minoAccent))
                    .scaleEffect(1.5)

                Text(job?.state.statusMessage ?? "Merging...")
                    .font(.headline)
                    .foregroundStyle(.white)

                if let progress = job?.state.progress, progress > 0 {
                    ProgressView(value: progress)
                        .tint(Color.minoAccent)
                        .frame(width: 200)
                }
            }
            .padding(32)
            .minoGlass(in: 20)
        }
    }
}

// MARK: - Merge Result View

struct MergeResultView: View {
    let result: MergeResult
    let onDone: () -> Void

    @State private var showingExportPicker = false
    @State private var showingPDFViewer = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Success icon
                ZStack {
                    Circle()
                        .fill(Color.minoSuccess.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.minoSuccess)
                }

                // Title
                VStack(spacing: 8) {
                    Text("Merge Complete!")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(result.summary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Stats card
                VStack(spacing: 12) {
                    StatRow(icon: "doc.fill", label: "Output File", value: result.fileName)
                    StatRow(icon: "doc.on.doc", label: "Files Merged", value: "\(result.sourceCount)")
                    StatRow(icon: "number", label: "Total Pages", value: "\(result.totalPages)")
                    StatRow(icon: "internaldrive", label: "File Size", value: result.formattedSize)
                    StatRow(icon: "clock", label: "Duration", value: result.formattedDuration)
                }
                .padding()
                .minoGlass(in: 16)
                .padding(.horizontal)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // View PDF - primary action
                    Button {
                        showingPDFViewer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("View PDF")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .minoGlassAccentButton()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Secondary actions row
                    HStack(spacing: 12) {
                        ShareLink(item: result.outputURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingExportPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text("Save to Files")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
            .background(Color.minoBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Record good merge and potentially request review
                        HistoryManager.shared.recordGoodMerge()
                        HistoryManager.shared.requestReviewIfAppropriate()
                        onDone()
                    }
                }
            }
            .minoToolbarStyle()
            .sheet(isPresented: $showingExportPicker) {
                DocumentExporter(url: result.outputURL) { _ in
                    showingExportPicker = false
                }
            }
            .fullScreenCover(isPresented: $showingPDFViewer) {
                PDFViewerView(documentURL: result.outputURL)
            }
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.minoAccent)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

#Preview {
    MergeView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
