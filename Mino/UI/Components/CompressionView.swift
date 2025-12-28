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

    let document: PDFDocumentInfo

    @State private var selectedQuality: CompressionQuality = .medium
    @State private var isAdvancedMode = false
    @State private var customSettings = CompressionSettings.default
    @State private var isCompressing = false
    @State private var currentPhase: CompressionPhase = .opening

    /// Current settings based on mode
    private var currentSettings: CompressionSettings {
        isAdvancedMode ? customSettings : selectedQuality.settings
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Document info
                            DocumentInfoHeader(document: document)

                            Divider()

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
                        .background(.bar)
                }

                // Compression overlay
                if isCompressing {
                    CompressionOverlay(
                        currentPhase: currentPhase,
                        fileName: document.name
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCompressing)
            .navigationTitle("Compress PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCompressing)
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
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("", isOn: $isAdvancedMode)
                .labelsHidden()
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
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                Text("Compress PDF")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startCompression() {
        // Show overlay immediately
        isCompressing = true
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
                dismiss()
                appState.showResults(result)
            } catch {
                isCompressing = false
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
                    .foregroundStyle(.secondary)
                Text(settings.technicalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

                Spacer()

                Text("\(Int(value))\(unit)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: step)
                .tint(Color.accentColor)

            Text(description)
                .font(.caption2)
                .foregroundStyle(.tertiary)
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

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

// MARK: - Document Info Header

struct DocumentInfoHeader: View {
    let document: PDFDocumentInfo

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(document.formattedPageCount)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(document.formattedSize)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Quality Selector

struct QualitySelector: View {
    @Binding var selectedQuality: CompressionQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compression Quality")
                .font(.headline)

            VStack(spacing: 8) {
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

                    Text("(\(quality.technicalDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(quality.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Expected reduction: \(quality.expectedReduction)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    let document = PDFDocumentInfo(
        url: URL(fileURLWithPath: "/test.pdf"),
        pageCount: 10
    )

    return CompressionView(document: document)
        .environment(AppState())
}
