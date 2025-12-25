//
//  StatisticsView.swift
//  Mino
//
//  View showing compression statistics and history
//

import SwiftUI

struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss

    private let historyManager = HistoryManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats cards
                    statsGrid

                    // History section
                    if !historyManager.history.isEmpty {
                        historySection
                    } else {
                        emptyHistoryView
                    }
                }
                .padding()
            }
            .background(Color.minoGradient.opacity(0.1).ignoresSafeArea())
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if !historyManager.history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) {
                            historyManager.clearHistory()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Files Compressed",
                value: "\(historyManager.totalFilesCompressed)",
                icon: "doc.zipper",
                color: .minoPrimary
            )

            StatCard(
                title: "Space Saved",
                value: historyManager.formattedTotalSaved,
                icon: "arrow.down.circle.fill",
                color: .minoSuccess
            )

            StatCard(
                title: "Avg Reduction",
                value: historyManager.formattedAverageReduction,
                icon: "percent",
                color: .minoAccent
            )

            StatCard(
                title: "Total Processed",
                value: historyManager.formattedTotalProcessed,
                icon: "arrow.triangle.2.circlepath",
                color: .minoSecondary
            )
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(historyManager.history.prefix(20)) { entry in
                    HistoryEntryRow(entry: entry)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Color.minoSecondary.opacity(0.5))

            Text("No compression history")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Compressed PDFs will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        }
    }
}

// MARK: - History Entry Row

struct HistoryEntryRow: View {
    let entry: CompressionHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(Color.minoAccent)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.originalFileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(entry.formattedOriginalSize)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(entry.formattedCompressedSize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Reduction
            VStack(alignment: .trailing, spacing: 2) {
                Text("-\(entry.formattedReduction)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.minoSuccess)

                Text(entry.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        }
    }
}

#Preview {
    StatisticsView()
}
