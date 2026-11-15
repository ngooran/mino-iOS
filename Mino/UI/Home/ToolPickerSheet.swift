//
//  ToolPickerSheet.swift
//  Mino
//
//  "What do you want to do?": the tools that work on an open PDF. Shown
//  after Open PDF, from Files, after a result and for incoming files.
//

import SwiftUI

struct ToolPickerSheet: View {
    let context: ToolPickerContext

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if context.documents.count == 1, let document = context.documents.first {
                        HStack {
                            DocumentRow(document: document, thumbnailWidth: 44)
                            Spacer(minLength: 8)
                            if document.wasLocked {
                                Image(systemName: "lock.open.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Unlocked")
                            }
                        }
                    } else {
                        ForEach(context.documents) { document in
                            DocumentRow(document: document)
                        }
                    }
                }

                Section {
                    ForEach(context.tools) { tool in
                        Button {
                            appState.pick(tool, from: context)
                        } label: {
                            ToolRow(tool: tool, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("What do you want to do?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // A sheet on one half of an open iPhone Duo can touch the hinge band.
        .avoidingFoldEdges()
    }
}

/// A tool as a list row: icon, name, what it does, and a PRO badge when it needs one.
struct ToolRow: View {
    let tool: Tool
    var showsChevron = false
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: tool.systemImage, color: tool.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                Text(tool.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if tool.access == .pro && !appState.isPro {
                ProBadge()
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
