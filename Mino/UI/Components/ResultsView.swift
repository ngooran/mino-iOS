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
    @State private var showingPDFViewer = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Success indicator
                        successHeader

                        // Size comparison
                        SizeComparisonCard(result: result)

                        // Statistics
                        statisticsCard

                        Spacer(minLength: 20)
                    }
                    .padding()
                }

                // Sticky action button
                actionButtons
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            .background(Color.minoBackground)
            .navigationTitle("Compression Complete")
            .navigationBarTitleDisplayMode(.inline)
            .minoToolbarStyle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showingExportPicker = true
                        } label: {
                            Label("Save to Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Record good compression and potentially request review
                        HistoryManager.shared.recordGoodCompression(reductionPercentage: result.reductionPercentage)
                        HistoryManager.shared.requestReviewIfAppropriate()
                        dismiss()
                    }
                    .foregroundStyle(Color.minoAccent)
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
            .fullScreenCover(isPresented: $showingPDFViewer) {
                PDFViewerView(documentURL: result.outputURL)
            }
        }
    }

    // MARK: - Views

    private var successHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.minoSuccess.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.minoSuccess)
                    .symbolEffect(.bounce, value: true)
            }

            Text("Success!")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("Your PDF has been compressed")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 20)
    }

    private var statisticsCard: some View {
        VStack(spacing: 16) {
            StatisticRow(
                icon: "arrow.down.circle",
                label: "Space Saved",
                value: result.formattedSavedBytes,
                color: Color.minoSuccess
            )

            Divider()
                .background(Color.minoCardBorder)

            StatisticRow(
                icon: "percent",
                label: "Reduction",
                value: result.formattedReduction,
                color: Color.minoAccent
            )

            Divider()
                .background(Color.minoCardBorder)

            StatisticRow(
                icon: "clock",
                label: "Duration",
                value: result.formattedDuration,
                color: .orange
            )

            Divider()
                .background(Color.minoCardBorder)

            StatisticRow(
                icon: "slider.horizontal.3",
                label: "Settings",
                value: result.settings.displayName,
                color: .purple
            )

            if result.settings.preset == nil {
                Divider()
                    .background(Color.minoCardBorder)

                StatisticRow(
                    icon: "photo",
                    label: "Image Quality",
                    value: "\(result.settings.jpegQuality)%",
                    color: .cyan
                )

                Divider()
                    .background(Color.minoCardBorder)

                StatisticRow(
                    icon: "square.resize",
                    label: "Target DPI",
                    value: "\(result.settings.targetDPI)",
                    color: .indigo
                )
            }
        }
        .padding()
        .background(Color.minoCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.minoCardBorder, lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        // View PDF button only - Share/Save moved to toolbar menu
        Button {
            showingPDFViewer = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                Text("View PDF")
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
                    .foregroundStyle(.white.opacity(0.5))

                Text(result.formattedOriginalSize)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Image(systemName: "doc.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)

            // Arrow
            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(Color.minoAccent)

                Text("-\(result.formattedReduction)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.minoSuccess)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.minoSuccess.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Compressed
            VStack(spacing: 8) {
                Text("Compressed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(result.formattedCompressedSize)
                    .font(.title2.bold())
                    .foregroundStyle(Color.minoSuccess)

                Image(systemName: "doc.zipper")
                    .font(.title)
                    .foregroundStyle(Color.minoSuccess)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.minoCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.minoCardBorder, lineWidth: 1)
        )
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
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
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
        .preferredColorScheme(.dark)
}
