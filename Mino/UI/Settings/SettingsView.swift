//
//  SettingsView.swift
//  Mino
//
//  Pro status first, then defaults, savings, support and about.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKeys.defaultQuality) private var defaultQuality: CompressionQuality = .medium
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.photoPageSize) private var photoPageSize: PhotoPageSize = .fit
    @AppStorage(SettingsKeys.scanFilter) private var scanFilter: ScanFilter = .color
    @AppStorage(SettingsKeys.officePageSize) private var officePageSize: OfficePageSize = .regional
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section {
                proRow
            }

            Section("Defaults") {
                Picker(selection: $defaultQuality) {
                    ForEach(CompressionQuality.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Quality") } icon: { IconTile(systemImage: "arrow.down.doc.fill", color: .teal) }
                }
                if Tool.scan.isAvailable {
                    Picker(selection: $scanFilter) {
                        ForEach(ScanFilter.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label { Text("Scan Filter") } icon: { IconTile(systemImage: "doc.viewfinder", color: .teal) }
                    }
                }
                if Tool.photosToPDF.isAvailable {
                    Picker(selection: $photoPageSize) {
                        ForEach(PhotoPageSize.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label { Text("Photo Page Size") } icon: { IconTile(systemImage: "photo.on.rectangle", color: .green) }
                    }
                }
                if Tool.officeToPDF.isAvailable {
                    Picker(selection: $officePageSize) {
                        ForEach(OfficePageSize.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label { Text("Office Page Size") } icon: { IconTile(systemImage: "doc.richtext.fill", color: .blue) }
                    }
                }
                Picker(selection: $appearance) {
                    ForEach(AppearanceOption.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Appearance") } icon: { IconTile(systemImage: "circle.lefthalf.filled", color: .indigo) }
                }
            }

            if Tool.fillSign.isAvailable {
                Section {
                    ForEach(SignatureKind.allCases) { kind in
                        HStack(spacing: 12) {
                            IconTile(systemImage: kind == .signature ? "signature" : "textformat.abc", color: .pink)
                            Text(kind == .signature ? "Signature" : "Initials")
                            Spacer()
                            if let image = appState.signatures.image(for: kind) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 90, height: 30)
                                    .padding(.horizontal, 6)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .accessibilityLabel("Saved")
                                Button(role: .destructive) {
                                    appState.signatures.delete(kind)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(kind == .signature ? "Delete Signature" : "Delete Initials")
                            } else {
                                Text("None").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Signing")
                } footer: {
                    Text("Your signature is stored on this \(deviceName) only. You draw it in Fill & Sign.")
                }
            }

            Section("Your Savings") {
                Button {
                    appState.show(.statistics, in: .settings)
                } label: {
                    HStack {
                        Label { Text("Statistics").foregroundStyle(.primary) } icon: { IconTile(systemImage: "chart.bar.fill", color: .green) }
                        Spacer()
                        Text(HistoryManager.shared.formattedTotalSaved + " saved")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(sizeClass == .regular && (appState.settingsPath.isEmpty || appState.settingsPath.first == .statistics) ? Color.accentColor.opacity(0.15) : nil)
            }

            Section("Support") {
                Link(destination: MinoLinks.writeReview) {
                    Label { Text("Rate Mino").foregroundStyle(.primary) } icon: { IconTile(systemImage: "star.fill", color: .yellow) }
                }
                .tint(.primary)
                ShareLink(item: MinoLinks.appStore, subject: Text("Mino – PDF Toolkit"), message: Text("I use Mino for PDFs. Everything stays on the device.")) {
                    Label { Text("Share Mino").foregroundStyle(.primary) } icon: { IconTile(systemImage: "square.and.arrow.up", color: .blue) }
                }
                .tint(.primary)
                Link(destination: MinoLinks.support) {
                    Label { Text("Help & Support").foregroundStyle(.primary) } icon: { IconTile(systemImage: "questionmark.circle.fill", color: .green) }
                }
                .tint(.primary)
                Button {
                    Task { await restore() }
                } label: {
                    HStack {
                        Label { Text("Restore Purchases").foregroundStyle(.primary) } icon: { IconTile(systemImage: "arrow.clockwise", color: .gray) }
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isRestoring)
            }

            Section {
                Link(destination: MinoLinks.privacy) {
                    Label { Text("Privacy Policy").foregroundStyle(.primary) } icon: { IconTile(systemImage: "hand.raised.fill", color: .indigo) }
                }
                .tint(.primary)
                Link(destination: MinoLinks.sourceCode) {
                    Label { Text("Source Code").foregroundStyle(.primary) } icon: { IconTile(systemImage: "chevron.left.forwardslash.chevron.right", color: .gray) }
                }
                .tint(.primary)
                LabeledContent {
                    Text(appVersion)
                } label: {
                    Label { Text("Version") } icon: { IconTile(systemImage: "info", color: .gray) }
                }
            } header: {
                Text("About")
            } footer: {
                Text("Mino processes your files on this \(deviceName) and never uploads them. Mino is open source under the AGPL-3.0 license and uses MuPDF by Artifex Software.")
            }

            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle("Settings")
        .alert("Restore Purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    // MARK: - Pro

    @ViewBuilder
    private var proRow: some View {
        if appState.isPro {
            HStack(spacing: 14) {
                AppIconView(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mino Pro").font(.headline)
                    Text(appState.store.isLegacyPurchaser
                         ? String(localized: "Unlocked. Thank you for buying Mino early.")
                         : String(localized: "Unlocked. Thank you for supporting Mino."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                appState.showPaywall(.general)
            } label: {
                HStack(spacing: 14) {
                    AppIconView(size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get Mino Pro").font(.headline).foregroundStyle(.primary)
                        Text("Every tool, unlimited. One-time purchase.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let unlocked = try await appState.store.restore()
            restoreMessage = unlocked
                ? String(localized: "Mino Pro is unlocked on this \(deviceName).")
                : String(localized: "No Mino Pro purchase was found for this Apple Account.")
        } catch {
            restoreMessage = error.localizedDescription
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Picker("Pro state", selection: Binding(
                get: { appState.store.debugProOverride.map { $0 ? 1 : 0 } ?? -1 },
                set: { appState.store.debugProOverride = $0 == -1 ? nil : $0 == 1 }
            )) {
                Text("StoreKit").tag(-1)
                Text("Free").tag(0)
                Text("Pro").tag(1)
            }
            LabeledContent("Free left today", value: "\(appState.usage.remaining)")
            Button("Reset Free Actions") { appState.usage.reset() }
            NavigationLink("App Icon Export") { AppIconExportView() }
        }
    }
    #endif
}

// MARK: - Statistics

struct StatisticsView: View {
    private let history = HistoryManager.shared

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(title: String(localized: "Space saved"), value: history.formattedTotalSaved, prominent: true)
                        .gridCellColumns(2)
                    StatTile(title: String(localized: "Files compressed"), value: String(localized: "\(history.totalFilesCompressed)"))
                    StatTile(title: String(localized: "Average reduction"), value: String(localized: "\(Int(history.averageReduction.rounded()))%"))
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Recent Activity") {
                if history.history.isEmpty {
                    Text("Compressed files will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history.history.prefix(50)) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.originalFileName)
                                    .lineLimit(1)
                                Text("\(entry.formattedOriginalSize) → \(entry.formattedCompressedSize) · \(entry.formattedTimestamp)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("−\(Int(entry.reductionPercentage.rounded()))%")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Statistics")
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: prominent ? 40 : 28, weight: .bold, design: .rounded))
                .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}
