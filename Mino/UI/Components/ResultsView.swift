//
//  ResultsView.swift
//  Mino
//
//  View showing compression results with before/after comparison
//

import SwiftUI

struct ResultsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let result: CompressionResult

    @State private var showingShareSheet = false
    @State private var showingExportPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Success indicator
                    successHeader

                    // Size comparison
                    SizeComparisonCard(result: result)

                    // Statistics
                    statisticsCard

                    // Action buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Compression Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [result.outputURL])
            }
            .sheet(isPresented: $showingExportPicker) {
                DocumentExporter(url: result.outputURL) { success in
                    showingExportPicker = false
                }
            }
        }
    }

    // MARK: - Views

    private var successHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)

            Text("Success!")
                .font(.title.bold())

            Text("Your PDF has been compressed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var statisticsCard: some View {
        VStack(spacing: 16) {
            StatisticRow(
                icon: "arrow.down.circle",
                label: "Space Saved",
                value: result.formattedSavedBytes,
                color: .green
            )

            Divider()

            StatisticRow(
                icon: "percent",
                label: "Reduction",
                value: result.formattedReduction,
                color: .blue
            )

            Divider()

            StatisticRow(
                icon: "clock",
                label: "Duration",
                value: result.formattedDuration,
                color: .orange
            )

            Divider()

            StatisticRow(
                icon: "slider.horizontal.3",
                label: "Settings",
                value: result.settings.displayName,
                color: .purple
            )

            if result.settings.preset == nil {
                Divider()

                StatisticRow(
                    icon: "photo",
                    label: "Image Quality",
                    value: "\(result.settings.jpegQuality)%",
                    color: .cyan
                )

                Divider()

                StatisticRow(
                    icon: "square.resize",
                    label: "Target DPI",
                    value: "\(result.settings.targetDPI)",
                    color: .indigo
                )
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Share button
            Button {
                showingShareSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    Text("Share")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            // Save to Files button
            Button {
                showingExportPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.title3)
                    Text("Save to Files")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.secondary.opacity(0.2))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Size Comparison Card

struct SizeComparisonCard: View {
    let result: CompressionResult

    var body: some View {
        HStack(spacing: 20) {
            // Original
            VStack(spacing: 8) {
                Text("Original")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(result.formattedOriginalSize)
                    .font(.title2.bold())

                Image(systemName: "doc.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Arrow
            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                Text("-\(result.formattedReduction)")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }

            // Compressed
            VStack(spacing: 8) {
                Text("Compressed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(result.formattedCompressedSize)
                    .font(.title2.bold())
                    .foregroundStyle(.green)

                Image(systemName: "doc.zipper")
                    .font(.title)
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Statistic Row

struct StatisticRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    let result = CompressionResult(
        outputURL: URL(fileURLWithPath: "/test_compressed.pdf"),
        originalSize: 104_857_600, // 100 MB
        compressedSize: 10_485_760, // 10 MB
        quality: .medium,
        duration: 12.5
    )

    return ResultsView(result: result)
        .environment(AppState())
}
