//
//  BatchCompressionView.swift
//  Mino
//
//  View for batch compressing multiple PDFs
//

import SwiftUI

struct BatchCompressionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let documents: [PDFDocumentInfo]

    @State private var selectedQuality: CompressionQuality = .medium
    @State private var isAdvancedMode = false
    @State private var customSettings = CompressionSettings.default
    @State private var isCompressing = false
    @State private var showingResults = false

    private var queue: BatchCompressionQueue? {
        appState.batchCompressionService.currentQueue
    }

    /// Current settings based on mode
    private var currentSettings: CompressionSettings {
        isAdvancedMode ? customSettings : selectedQuality.settings
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress header
                if let queue = queue, isCompressing {
                    progressHeader(queue: queue)
                }

                // Document list
                documentList

                // Bottom bar with quality selector and start button
                if !isCompressing {
                    bottomBar
                }
            }
            .background(Color.minoBackground)
            .navigationTitle("Batch Compression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isCompressing ? "Cancel" : "Close") {
                        if isCompressing {
                            appState.batchCompressionService.cancelBatch()
                        }
                        dismiss()
                    }
                }
            }
            .minoToolbarStyle()
            .onAppear {
                // Clear any previous queue when view appears with new documents
                appState.batchCompressionService.clearQueue()
            }
            .sheet(isPresented: $showingResults) {
                if let queue = queue {
                    BatchResultsView(queue: queue) {
                        showingResults = false
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Progress Header

    private func progressHeader(queue: BatchCompressionQueue) -> some View {
        VStack(spacing: 12) {
            // Progress bar
            ProgressView(value: queue.state.progress)
                .tint(Color.minoAccent)

            // Status text
            HStack {
                Text(queue.state.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(queue.completedCount)/\(queue.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding()
        .background(Color.minoCardBackground)
    }

    // MARK: - Document List

    private var documentList: some View {
        List {
            Section {
                if let queue = queue {
                    ForEach(queue.items) { item in
                        BatchDocumentRow(item: item)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(documents) { document in
                        PendingDocumentRow(document: document)
                            .listRowSeparator(.hidden)
                    }
                }
            } header: {
                Text("\(queue?.items.count ?? documents.count) FILES")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Advanced mode toggle
            HStack {
                Text("Advanced Settings")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Toggle("", isOn: $isAdvancedMode)
                    .labelsHidden()
                    .tint(Color.minoAccent)
                    .onChange(of: isAdvancedMode) { _, newValue in
                        if newValue {
                            customSettings = selectedQuality.settings
                            customSettings.preset = nil
                        }
                    }
            }
            .padding(.horizontal)

            // Quality selector or advanced settings
            if isAdvancedMode {
                AdvancedSettingsView(settings: $customSettings)
                    .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COMPRESSION QUALITY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.5)

                    HStack(spacing: 10) {
                        ForEach(CompressionQuality.allCases, id: \.self) { quality in
                            QualityButton(
                                quality: quality,
                                isSelected: selectedQuality == quality
                            ) {
                                selectedQuality = quality
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Summary
            HStack {
                Text("Total: \(totalPages) pages")
                Spacer()
                Text(totalSize)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal)

            // Start button
            Button {
                Task {
                    await startBatchCompression()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Compress \(documents.count) PDFs")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .minoGlassAccentButton()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.minoCardBackground)
    }

    // MARK: - Computed Properties

    private var totalPages: Int {
        documents.reduce(0) { $0 + $1.pageCount }
    }

    private var totalSize: String {
        let bytes = documents.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Actions

    private func startBatchCompression() async {
        isCompressing = true
        HapticManager.shared.compressionStart()

        do {
            let results = try await appState.batchCompressionService.startBatch(
                documents: documents,
                settings: currentSettings
            )

            // Add results to compression service so they show in Files tab
            for result in results {
                appState.compressionService.addBatchResult(result)
            }

            isCompressing = false
            HapticManager.shared.compressionComplete()
            showingResults = true
        } catch {
            isCompressing = false
            HapticManager.shared.error()
            appState.showError(error)
        }
    }
}

// MARK: - Quality Button

struct QualityButton: View {
    let quality: CompressionQuality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(quality.rawValue)
                    .font(.subheadline.weight(.medium))

                Text(quality.expectedReduction)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(isSelected ? Color.minoAccent : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Batch Document Row

struct BatchDocumentRow: View {
    let item: BatchCompressionItem

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon

            // Document info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.document.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.document.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Result or status
            statusBadge
        }
        .listRowBackground(Color.minoCardBackground)
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.15))
                .frame(width: 40, height: 40)

            if item.state.isActive {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: statusIconName)
                    .font(.system(size: 16))
                    .foregroundStyle(statusColor)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.state {
        case .pending:
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

        case .compressing(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.minoAccent)

        case .completed(let result):
            Text("-\(result.formattedReduction)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.minoSuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.minoSuccess.opacity(0.15))
                .clipShape(Capsule())

        case .failed:
            Text("Failed")
                .font(.caption)
                .foregroundStyle(Color.minoError)

        case .skipped:
            Text("Skipped")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .pending:
            return .white.opacity(0.3)
        case .compressing:
            return Color.minoAccent
        case .completed:
            return Color.minoSuccess
        case .failed:
            return Color.minoError
        case .skipped:
            return .white.opacity(0.3)
        }
    }

    private var statusIconName: String {
        switch item.state {
        case .pending:
            return "clock"
        case .compressing:
            return "arrow.down.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .skipped:
            return "forward.fill"
        }
    }
}

// MARK: - Pending Document Row

struct PendingDocumentRow: View {
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

                Text(document.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .listRowBackground(Color.minoCardBackground)
    }
}

// MARK: - Batch Results View

struct BatchResultsView: View {
    let queue: BatchCompressionQueue
    let onDone: () -> Void

    @State private var fileToPreview: PreviewFile?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Success header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.minoSuccess.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.minoSuccess)
                    }

                    Text("Batch Complete!")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text("\(queue.completedCount) of \(queue.count) files compressed")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top)

                // Stats
                VStack(spacing: 12) {
                    StatRow(icon: "arrow.down.doc", label: "Space Saved", value: queue.formattedBytesSaved)
                    StatRow(icon: "percent", label: "Avg. Reduction", value: queue.formattedAverageReduction)
                    if let duration = queue.formattedDuration {
                        StatRow(icon: "clock", label: "Total Time", value: duration)
                    }
                }
                .padding()
                .minoGlass(in: 16)
                .padding(.horizontal)

                // Results list
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(queue.results) { result in
                            Button {
                                fileToPreview = PreviewFile(url: result.outputURL)
                            } label: {
                                CompressedFileCard(result: result)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(BatchResultCardButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(Color.minoBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Record good compressions and potentially request review
                        for result in queue.results {
                            HistoryManager.shared.recordGoodCompression(reductionPercentage: result.reductionPercentage)
                        }
                        HistoryManager.shared.requestReviewIfAppropriate()
                        onDone()
                    }
                }
            }
            .minoToolbarStyle()
            .fullScreenCover(item: $fileToPreview) { file in
                PDFViewerView(documentURL: file.url)
            }
        }
    }
}

// MARK: - Batch Result Card Button Style

struct BatchResultCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    BatchCompressionView(documents: [])
        .environment(AppState())
        .preferredColorScheme(.dark)
}
