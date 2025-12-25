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
    @State private var compressionProgress: Double = 0
    @State private var progressMessage: String = "Preparing..."

    /// Current settings based on mode
    private var currentSettings: CompressionSettings {
        isAdvancedMode ? customSettings : selectedQuality.settings
    }

    var body: some View {
        NavigationStack {
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

                    // Compress button or progress
                    if isCompressing {
                        CompressionProgressSection(
                            progress: compressionProgress,
                            message: progressMessage
                        )
                    } else {
                        compressButton
                    }
                }
                .padding()
            }
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
        isCompressing = true
        compressionProgress = 0
        progressMessage = "Preparing..."

        Task {
            do {
                let result = try await appState.compressionService.compress(
                    document: document,
                    settings: currentSettings
                )

                await MainActor.run {
                    isCompressing = false
                    dismiss()
                    appState.showResults(result)
                }
            } catch {
                await MainActor.run {
                    isCompressing = false
                    appState.showError(error)
                }
            }
        }
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

// MARK: - Compression Progress Section

struct CompressionProgressSection: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.title.monospacedDigit())
                    .fontWeight(.semibold)
            }
            .frame(width: 100, height: 100)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView()
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 20)
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
