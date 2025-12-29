//
//  StatisticsView.swift
//  Mino
//
//  View showing compression statistics and history
//

import SwiftUI

struct StatisticsView: View {
    @Environment(AppState.self) private var appState
    private let historyManager = HistoryManager.shared

    @State private var showingClearConfirmation = false

    private var recentResults: [CompressionResult] {
        appState.compressionService.recentResults
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stats cards
                statsGrid

                // History section (using same cards as HomeView)
                if !recentResults.isEmpty {
                    historySection
                } else {
                    emptyHistoryView
                }
            }
            .padding()
        }
        .background(Color.minoBackground)
        .minoToolbarStyle()
        .toolbar {
            if !recentResults.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .alert(
            "Clear History",
            isPresented: $showingClearConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.compressionService.clearAllResults()
            }
        } message: {
            Text("This will permanently delete all compressed files.")
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
            Text("RECENT ACTIVITY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)

            VStack(spacing: 10) {
                ForEach(recentResults.prefix(20)) { result in
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

    // MARK: - Empty State

    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.minoAccent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.minoAccent.opacity(0.6))
            }

            Text("No compression history")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            Text("Compressed PDFs will appear here")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
        .minoGlass(in: 14)
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
