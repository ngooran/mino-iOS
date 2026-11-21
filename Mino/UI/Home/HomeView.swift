//
//  HomeView.swift
//  Mino
//
//  The toolkit: search, the fastest ways to start, tools grouped by what
//  you want to do, and recent files.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    private var query: String { appState.toolQuery }

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    entryPoints
                    FreeAllowanceView()
                    ForEach(Tool.Category.allCases) { category in
                        let tools = category.tools
                        if !tools.isEmpty {
                            SectionTitle(category.title)
                            ToolGrid(tools: tools)
                        }
                    }
                    recentSection
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Mino")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $state.toolQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tools")
    }

    // MARK: - Entry points

    /// Scan (once it ships) and Open PDF, side by side.
    private var entryPoints: some View {
        HStack(spacing: 12) {
            if Tool.scan.isAvailable {
                EntryButton(title: String(localized: "Scan"), systemImage: "doc.viewfinder", prominent: true) {
                    appState.open(.scan)
                }
            }
            EntryButton(title: String(localized: "Open PDF"), systemImage: "doc", prominent: !Tool.scan.isAvailable) {
                appState.openPDF()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Search

    @ViewBuilder
    private var searchResults: some View {
        let hits = Tool.available.filter { $0.matches(query) }
        if hits.isEmpty {
            ContentUnavailableView {
                Label("No Tool Found", systemImage: "magnifyingglass")
            } description: {
                Text("No tool matches “\(query)”.")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element) { index, tool in
                    Button {
                        appState.toolQuery = ""
                        appState.open(tool)
                    } label: {
                        ToolRow(tool: tool)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    if index < hits.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(appState.files.prefix(3))
        if !recent.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(String(localized: "Recent"))
                Spacer()
                Button("See All") {
                    appState.selectedTab = .files
                }
            }
            .padding(.trailing, 4)

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

// MARK: - Pieces

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A large start button: Scan or Open PDF.
private struct EntryButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(14)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.cardBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
}

/// Tools in two columns. A lone last tool takes the full width.
private struct ToolGrid: View {
    let tools: [Tool]

    var body: some View {
        let rows = stride(from: 0, to: tools.count, by: 2).map { Array(tools[$0..<min($0 + 2, tools.count)]) }
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row) { tool in
                        ToolTile(tool: tool, wide: row.count == 1)
                    }
                }
                // Both tiles take the height of the taller one.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ToolTile: View {
    let tool: Tool
    let wide: Bool
    @Environment(AppState.self) private var appState

    private var showsPro: Bool { tool.access == .pro && !appState.isPro }

    var body: some View {
        Button {
            appState.open(tool)
        } label: {
            Group {
                if wide {
                    HStack(spacing: 12) {
                        IconTile(systemImage: tool.systemImage, color: tool.color, size: 36)
                        titles
                        Spacer(minLength: 4)
                        badge
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top) {
                            IconTile(systemImage: tool.systemImage, color: tool.color, size: 36)
                            Spacer()
                            badge
                        }
                        .padding(.bottom, 8)
                        titles
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(padding: 14, cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityHint(showsPro ? String(localized: "Requires Mino Pro") : "")
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tool.title)
                .font(.headline)
            Text(tool.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if showsPro {
            ProBadge()
        } else if tool.isNew {
            NewBadge()
        }
    }
}

// MARK: - Start pane (regular width, nothing open)

/// The trailing column of Home on iPad and the open iPhone Duo when no tool or
/// file is open: recent files to pick up again, a few tools to start with, and
/// the reminder that files can be dropped here. Without files yet, large ways
/// to start.
struct HomeStartView: View {
    @Environment(AppState.self) private var appState

    /// The tools most people start with; the full list is on the left.
    private let quickTools: [Tool] = [.fillSign, .compress, .photosToPDF, .officeToPDF]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let recent = Array(appState.files.prefix(6))
                if recent.isEmpty {
                    firstStart
                } else {
                    PaneTitle(String(localized: "Recent"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)], spacing: 14) {
                        ForEach(recent) { item in
                            RecentCard(item: item)
                        }
                    }
                    PaneTitle(String(localized: "Start Something New"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(quickTools.filter(\.isAvailable)) { tool in
                            QuickToolButton(tool: tool)
                        }
                    }
                }
                Label("Drop PDFs or photos here to start.", systemImage: "square.and.arrow.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }

    /// No files yet: the three ways to begin, large.
    private var firstStart: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneTitle(String(localized: "Start with a Document"))
            HStack(spacing: 14) {
                if Tool.scan.isAvailable {
                    EntryButton(title: String(localized: "Scan"), systemImage: "doc.viewfinder", prominent: true) {
                        appState.open(.scan)
                    }
                }
                EntryButton(title: String(localized: "Open PDF"), systemImage: "doc", prominent: !Tool.scan.isAvailable) {
                    appState.openPDF()
                }
                EntryButton(title: Tool.photosToPDF.title, systemImage: Tool.photosToPDF.systemImage, prominent: false) {
                    appState.open(.photosToPDF)
                }
            }
            .frame(height: 130)
        }
    }
}

private struct PaneTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A recent file: a large first-page thumbnail, its name and what made it.
private struct RecentCard: View {
    let item: FileItem
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.show(.preview(item), in: .home)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                FileThumbnail(url: item.url, width: 118)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Label(item.kind.title, systemImage: item.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 14, cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Opens a preview"))
    }
}

/// One tool as a wide row: icon, title, subtitle, Pro badge when locked.
private struct QuickToolButton: View {
    let tool: Tool
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.open(tool)
        } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: tool.systemImage, color: tool.color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.headline)
                    Text(tool.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if tool.access == .pro && !appState.isPro {
                    ProBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 14, cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
    }
}
