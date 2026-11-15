//
//  HomeView.swift
//  Mino
//
//  One obvious first step (Compress), two tools, and recent files.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                compressCard

                HStack(spacing: 12) {
                    ToolTile(
                        title: "Merge",
                        subtitle: "Combine PDFs into one",
                        systemImage: "doc.on.doc.fill",
                        color: .indigo,
                        showsPro: !appState.isPro
                    ) {
                        appState.openMerge()
                    }
                    ToolTile(
                        title: "Split",
                        subtitle: "Extract or separate pages",
                        systemImage: "scissors",
                        color: .orange,
                        showsPro: !appState.isPro
                    ) {
                        appState.openSplit()
                    }
                }
                // Both tiles take the height of the taller one.
                .fixedSize(horizontal: false, vertical: true)

                recentSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Mino")
    }

    // MARK: - Compress

    private var compressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.bottom, 6)
                .accessibilityHidden(true)

            Text("Compress a PDF")
                .font(.title2.bold())

            Text("Make big files small enough to email or message. Nothing leaves your \(deviceName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appState.chooseFilesToCompress()
            } label: {
                ActionLabel(title: "Choose PDF", systemImage: "plus")
            }
            .primaryButtonStyle()
            .padding(.top, 10)

            FreeAllowanceView()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20, cornerRadius: 30)
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(appState.files.prefix(3))
        if !recent.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See All") {
                    appState.selectedTab = .files
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                    Button {
                        appState.show(.preview(item), in: .home)
                    } label: {
                        FileRow(item: item)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .background(isOpen(item) ? Color.accentColor.opacity(0.12) : .clear)

                    if index < recent.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            let history = HistoryManager.shared
            if history.totalBytesSaved > 0 {
                Label("\(history.formattedTotalSaved) saved with Mino so far", systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func isOpen(_ item: FileItem) -> Bool {
        appState.homePath.first == .preview(item)
    }
}

// MARK: - Tool tile

private struct ToolTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let showsPro: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    IconTile(systemImage: systemImage, color: color, size: 36)
                    Spacer()
                    if showsPro { ProBadge() }
                }
                .padding(.bottom, 8)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(padding: 14, cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityHint(showsPro ? "Requires Mino Pro" : "")
    }
}

// MARK: - Drop zone (regular width, nothing open)

struct HomeDropZone: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Drop PDFs Here", systemImage: "arrow.down.doc")
            } description: {
                Text("Drag PDFs from Files, Mail or Safari to compress them, or pick a tool on the left.")
            } actions: {
                Button("Choose PDF") { appState.chooseFilesToCompress() }
                    .secondaryButtonStyle()
            }
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.quaternary)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.groupedBackground)
    }
}
