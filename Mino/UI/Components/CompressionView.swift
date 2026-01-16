//
//  CompressionView.swift
//  Mino
//
//  View for configuring and running PDF compression
//

import SwiftUI

struct CompressionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let documents: [PDFDocumentInfo]

    @State private var selectedQuality: CompressionQuality = .medium
    @State private var isAdvancedMode = false
    @State private var customSettings = CompressionSettings.default
    @State private var isCompressing = false
    @State private var currentPhase: CompressionPhase = .opening

    /// Whether this is a batch compression (multiple files)
    private var isBatch: Bool { documents.count > 1 }

    /// Current settings based on mode
    private var currentSettings: CompressionSettings {
        isAdvancedMode ? customSettings : selectedQuality.settings
    }

    /// Total pages across all documents
    private var totalPages: Int {
        documents.reduce(0) { $0 + $1.pageCount }
    }

    /// Total size of all documents
    private var totalSize: String {
        let bytes = documents.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Document info - single or list
                            if isBatch {
                                DocumentListHeader(documents: documents)
                            } else if let document = documents.first {
                                DocumentInfoHeader(document: document)
                            }

                            Divider()
                                .background(Color.minoCardBorder)

                            // Mode toggle
                            modeToggle
                                .disabled(isCompressing)

                            // Quality selector or advanced settings
                            if isAdvancedMode {
                                AdvancedSettingsView(settings: $customSettings)
                                    .disabled(isCompressing)
                            } else {
                                QualitySelector(selectedQuality: $selectedQuality)
                                    .disabled(isCompressing)
                            }

                            Spacer(minLength: 20)
                        }
                        .padding()
                    }

                    // Sticky bottom button
                    compressButton
                        .disabled(isCompressing)
                        .opacity(isCompressing ? 0.5 : 1)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }

                // Compression overlay
                if isCompressing {
                    if isBatch {
                        BatchCompressionOverlay()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else if let document = documents.first {
                        CompressionOverlay(
                            currentPhase: currentPhase,
                            fileName: document.name
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }
            .background(Color.minoBackground)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCompressing)
            .navigationTitle(isBatch ? "Compress \(documents.count) PDFs" : "Compress PDF")
            .navigationBarTitleDisplayMode(.inline)
            .minoToolbarStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isCompressing ? "Cancel" : "Close") {
                        if isCompressing {
                            appState.batchCompressionService.cancelBatch()
                        }
                        dismiss()
                    }
                    .foregroundStyle(Color.minoAccent)
                }
            }
            .interactiveDismissDisabled(isCompressing)
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
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
                        // Initialize custom settings from current preset
                        customSettings = selectedQuality.settings
                        customSettings.preset = nil // Mark as custom
                    }
                }
        }
        .padding(.horizontal)
    }

    // MARK: - Views

    private var compressButton: some View {
        Button {
            startCompression()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isBatch ? "bolt.fill" : "arrow.down.circle.fill")
                    .font(.title2)
                Text(isBatch ? "Compress \(documents.count) PDFs" : "Compress PDF")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.minoAccent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startCompression() {
        isCompressing = true
        HapticManager.shared.compressionStart()

        if isBatch {
            startBatchCompression()
        } else {
            startSingleCompression()
        }
    }

    private func startSingleCompression() {
        guard let document = documents.first else { return }
        currentPhase = .opening

        Task {
            do {
                // Phase 1: Opening
                setPhase(.opening)
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Phase 2: Analyzing
                setPhase(.analyzing)
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Phase 3: Compressing (this is where actual work happens)
                setPhase(.compressing)

                let result = try await appState.compressionService.compress(
                    document: document,
                    settings: currentSettings
                )

                // Phase 4: Saving
                setPhase(.saving)
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Phase 5: Complete
                setPhase(.complete)
                try? await Task.sleep(nanoseconds: 600_000_000)

                isCompressing = false
                HapticManager.shared.compressionComplete()
                dismiss()
                appState.showResults(result)
            } catch {
                isCompressing = false
                HapticManager.shared.error()
                appState.showError(error)
            }
        }
    }

    private func startBatchCompression() {
        Task {
            do {
                let results = try await appState.batchCompressionService.startBatch(
                    documents: documents,
                    settings: currentSettings
                )

                // Add all results to compression service so they show in Files tab
                for result in results {
                    appState.compressionService.addBatchResult(result)
                }

                isCompressing = false
                HapticManager.shared.compressionComplete()
                dismiss()

                // Show summary for batch
                if !results.isEmpty {
                    appState.showBatchResults(results)
                }
            } catch {
                isCompressing = false
                HapticManager.shared.error()
                appState.showError(error)
            }
        }
    }

    private func setPhase(_ phase: CompressionPhase) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPhase = phase
        }
    }
}

// MARK: - Compression Phase

enum CompressionPhase: Int, CaseIterable {
    case opening = 0
    case analyzing = 1
    case compressing = 2
    case saving = 3
    case complete = 4

    var title: String {
        switch self {
        case .opening: return "Opening file"
        case .analyzing: return "Analyzing document"
        case .compressing: return "Compressing"
        case .saving: return "Saving file"
        case .complete: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .opening: return "doc"
        case .analyzing: return "magnifyingglass"
        case .compressing: return "arrow.down.circle"
        case .saving: return "square.and.arrow.down"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Compression Overlay

struct CompressionOverlay: View {
    let currentPhase: CompressionPhase
    let fileName: String

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Modal card
            VStack(spacing: 24) {
                // Header with icon
                ZStack {
                    Circle()
                        .fill(Color.minoAccent.opacity(0.15))
                        .frame(width: 80, height: 80)

                    if currentPhase == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.minoSuccess)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        SpinningDocIcon()
                    }
                }

                // Title
                Text(currentPhase == .complete ? "Compression Complete!" : "Compressing PDF")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                // File name
                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal)

                // Indeterminate progress bar
                if currentPhase != .complete {
                    IndeterminateProgressBar()
                        .padding(.horizontal, 8)
                }

                // Phase checklist
                VStack(spacing: 0) {
                    ForEach(CompressionPhase.allCases.filter { $0 != .complete }, id: \.rawValue) { phase in
                        PhaseRow(
                            phase: phase,
                            currentPhase: currentPhase
                        )
                    }
                }
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
    }
}

// MARK: - Spinning Doc Icon

struct SpinningDocIcon: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "doc.zipper")
            .font(.system(size: 36))
            .foregroundStyle(Color.minoAccent)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Phase Row

struct PhaseRow: View {
    let phase: CompressionPhase
    let currentPhase: CompressionPhase

    private var isComplete: Bool {
        phase.rawValue < currentPhase.rawValue
    }

    private var isCurrent: Bool {
        phase.rawValue == currentPhase.rawValue
    }

    private var isPending: Bool {
        phase.rawValue > currentPhase.rawValue
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.minoSuccess)
                        .transition(.scale.combined(with: .opacity))
                } else if isCurrent {
                    // Animated spinner
                    SpinnerIcon()
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 24, height: 24)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPhase)

            // Phase title
            Text(phase.title)
                .font(.subheadline)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isPending ? .secondary : .primary)

            Spacer()

            // Current indicator
            if isCurrent {
                Text("In Progress")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.minoAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.minoAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Spinner Icon

struct SpinnerIcon: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.minoAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Indeterminate Progress Bar

struct IndeterminateProgressBar: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)

                // Animated bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color.minoAccent.opacity(0.3), Color.minoAccent, Color.minoAccentLight, Color.minoAccent, Color.minoAccent.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.4, height: 6)
                    .offset(x: offset * width)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    offset = 0.6
                }
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Advanced Settings View

struct AdvancedSettingsView: View {
    @Binding var settings: CompressionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Custom Settings")
                .font(.headline)
                .foregroundStyle(.white)

            // JPEG Quality
            SettingSlider(
                title: "Image Quality",
                value: Binding(
                    get: { Double(settings.jpegQuality) },
                    set: { settings.jpegQuality = Int($0) }
                ),
                range: 10...100,
                step: 5,
                unit: "%",
                description: "Lower = smaller file, reduced quality"
            )

            // Target DPI
            SettingSlider(
                title: "Target DPI",
                value: Binding(
                    get: { Double(settings.targetDPI) },
                    set: { settings.targetDPI = Int($0) }
                ),
                range: 50...300,
                step: 10,
                unit: " DPI",
                description: "Resolution for downsampled images"
            )

            // Garbage Collection Level
            SettingSlider(
                title: "Cleanup Level",
                value: Binding(
                    get: { Double(settings.garbageLevel) },
                    set: { settings.garbageLevel = Int($0) }
                ),
                range: 0...4,
                step: 1,
                unit: "",
                description: "Higher = more aggressive object cleanup"
            )

            Divider()
                .background(Color.minoCardBorder)

            // Toggle options
            VStack(spacing: 12) {
                SettingToggle(
                    title: "Compress Streams",
                    isOn: $settings.compressStreams,
                    description: "Deflate content streams"
                )

                SettingToggle(
                    title: "Compress Images",
                    isOn: $settings.compressImages,
                    description: "Recompress embedded images"
                )

                SettingToggle(
                    title: "Compress Fonts",
                    isOn: $settings.compressFonts,
                    description: "Optimize font data"
                )

                SettingToggle(
                    title: "Clean Content",
                    isOn: $settings.cleanContent,
                    description: "Sanitize page content"
                )
            }

            // Summary
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.white.opacity(0.5))
                Text(settings.technicalDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.minoCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.minoCardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Setting Slider

struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(Int(value))\(unit)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.minoAccent)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: step)
                .tint(Color.minoAccent)

            Text(description)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Setting Toggle

struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.minoAccent)
        }
    }
}

// MARK: - Document Info Header

struct DocumentInfoHeader: View {
    let document: PDFDocumentInfo

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.minoAccent.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.minoAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(document.formattedPageCount)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))

                Text(document.formattedSize)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding()
        .background(Color.minoCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.minoCardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Document List Header (for batch compression)

struct DocumentListHeader: View {
    let documents: [PDFDocumentInfo]

    private var totalPages: Int {
        documents.reduce(0) { $0 + $1.pageCount }
    }

    private var totalSize: String {
        let bytes = documents.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.minoAccent.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.minoAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(documents.count) PDFs Selected")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("\(totalPages) pages • \(totalSize)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
            }
            .padding()

            Divider()
                .background(Color.minoCardBorder)

            // Document list
            VStack(spacing: 0) {
                ForEach(documents) { document in
                    DocumentListRow(document: document)
                }
            }
        }
        .background(Color.minoCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.minoCardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Document List Row

struct DocumentListRow: View {
    let document: PDFDocumentInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.minoAccent.opacity(0.6))
                .frame(width: 24)

            Text(document.name)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(document.formattedSize)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Batch Compression Overlay

struct BatchCompressionOverlay: View {
    @Environment(AppState.self) private var appState

    private var queue: BatchCompressionQueue? {
        appState.batchCompressionService.currentQueue
    }

    private var progress: Double {
        guard let queue = queue, queue.count > 0 else { return 0 }
        return Double(queue.completedCount) / Double(queue.count)
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            // Modal card
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    // Spinning icon
                    ZStack {
                        Circle()
                            .fill(Color.minoAccent.opacity(0.15))
                            .frame(width: 64, height: 64)

                        SpinningDocIcon()
                    }

                    // Title and progress text
                    VStack(spacing: 4) {
                        Text("Compressing PDFs")
                            .font(.title3.bold())
                            .foregroundStyle(.white)

                        if let queue = queue {
                            Text("\(queue.completedCount) of \(queue.count) files completed")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    // Overall progress bar
                    VStack(spacing: 6) {
                        ProgressView(value: progress)
                            .tint(Color.minoAccent)

                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider()
                    .background(Color.white.opacity(0.1))

                // File list
                if let queue = queue {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                                    BatchFileProgressRow(
                                        index: index + 1,
                                        item: item
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                        .onChange(of: queue.currentIndex) { _, newIndex in
                            if let newIndex = newIndex,
                               let item = queue.item(at: newIndex) {
                                withAnimation {
                                    proxy.scrollTo(item.id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 340)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
    }
}

// MARK: - Batch File Progress Row

struct BatchFileProgressRow: View {
    let index: Int
    let item: BatchCompressionItem

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                if item.state.isActive {
                    // Spinning indicator for active
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.minoAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
            }

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.document.name)
                    .font(.subheadline.weight(item.state.isActive ? .semibold : .regular))
                    .foregroundStyle(item.state.isActive ? .white : .white.opacity(0.8))
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusTextColor)
            }

            Spacer()

            // Reduction badge for completed
            if case .completed(let result) = item.state {
                Text("-\(result.formattedReduction)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.minoSuccess)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.minoSuccess.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(item.state.isActive ? Color.minoAccent.opacity(0.1) : Color.clear)
    }

    @State private var rotationAngle: Double = 0

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

    private var statusIcon: String {
        switch item.state {
        case .pending:
            return "clock"
        case .compressing:
            return "arrow.down.circle"
        case .completed:
            return "checkmark"
        case .failed:
            return "xmark"
        case .skipped:
            return "forward.fill"
        }
    }

    private var statusText: String {
        switch item.state {
        case .pending:
            return "Waiting..."
        case .compressing:
            return "Compressing..."
        case .completed(let result):
            return "\(result.formattedOriginalSize) → \(result.formattedCompressedSize)"
        case .failed(let error):
            return error
        case .skipped:
            return "Skipped"
        }
    }

    private var statusTextColor: Color {
        switch item.state {
        case .pending:
            return .white.opacity(0.4)
        case .compressing:
            return Color.minoAccent
        case .completed:
            return .white.opacity(0.5)
        case .failed:
            return Color.minoError.opacity(0.8)
        case .skipped:
            return .white.opacity(0.4)
        }
    }
}

// MARK: - Quality Selector

struct QualitySelector: View {
    @Binding var selectedQuality: CompressionQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compression Quality")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                ForEach(CompressionQuality.allCases) { quality in
                    QualityOptionRow(
                        quality: quality,
                        isSelected: selectedQuality == quality
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedQuality = quality
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quality Option Row

struct QualityOptionRow: View {
    let quality: CompressionQuality
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(quality.rawValue)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("(\(quality.technicalDescription))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(quality.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                Text("Expected reduction: \(quality.expectedReduction)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.minoAccent : .white.opacity(0.3))
        }
        .padding()
        .background(isSelected ? Color.minoAccent.opacity(0.1) : Color.minoCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.minoAccent : Color.minoCardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    let document = PDFDocumentInfo(
        url: URL(fileURLWithPath: "/test.pdf"),
        pageCount: 10
    )

    return CompressionView(documents: [document])
        .environment(AppState())
        .preferredColorScheme(.dark)
}
