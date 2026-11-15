//
//  CompressFlowView.swift
//  Mino
//
//  Choose quality → compress → result, all in one screen so the task
//  keeps its place when the layout changes.
//

import SwiftUI

struct CompressFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.compressSession {
            CompressContent(session: session)
                .id(session.id)
        } else {
            ContentUnavailableView("No PDF Selected", systemImage: "doc", description: Text("Choose a PDF on Home to compress it."))
        }
    }
}

private struct CompressContent: View {
    @Bindable var session: CompressSession
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            switch session.phase {
            case .configure:
                configureView
            case .working:
                workingView
            case .done:
                CompressResultView(session: session)
            case .failed(let message):
                TaskFailedView(message: message) { session.phase = .configure }
            }
        }
        .navigationTitle(session.phase == .configure ? Tool.compress.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(session.phase != .configure)
        .toolbar {
            if sizeClass == .regular && session.phase == .configure {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { appState.closeTask() }
                }
            }
        }
    }

    // MARK: - Configure

    private var configureView: some View {
        List {
            Section {
                if session.isBatch {
                    ForEach(session.documents) { document in
                        DocumentRow(document: document)
                    }
                } else if let document = session.documents.first {
                    HStack {
                        DocumentRow(document: document, thumbnailWidth: 54)
                        Spacer(minLength: 8)
                        Button("Change") { appState.chooseFilesToCompress() }
                            .buttonStyle(.borderless)
                    }
                }
            } footer: {
                if session.isBatch {
                    Text("\(session.documents.count) PDFs · \(session.totalPages) pages · \(ByteCountFormatter.string(fromByteCount: session.totalSize, countStyle: .file))")
                }
            }

            Section {
                ForEach(CompressionQuality.allCases) { quality in
                    QualityRow(
                        quality: quality,
                        detail: detail(for: quality),
                        isSelected: session.choice == .preset(quality)
                    ) {
                        withAnimation { session.choice = .preset(quality) }
                    }
                }
                customRow
                if session.choice == .custom {
                    customControls
                }
            } header: {
                Text("Quality")
            } footer: {
                Label("Compressed on this \(deviceName). Your files are never uploaded.", systemImage: "lock.fill")
                    .padding(.top, 4)
            }
        }
        .listStyle(.insetGrouped)
        .bottomActions {
            Button {
                appState.compress(session)
            } label: {
                HStack(spacing: 8) {
                    Text(session.isBatch ? String(localized: "Compress \(session.documents.count) PDFs") : String(localized: "Compress"))
                    if session.isBatch && !appState.isPro { ProBadge() }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .primaryButtonStyle()
            .keyboardShortcut(.defaultAction)
        }
    }

    private func detail(for quality: CompressionQuality) -> String {
        if let estimate = session.estimates[quality] {
            if Double(estimate) >= Double(session.totalSize) * 0.97 {
                return String(localized: "About the same size · \(quality.useCase)")
            }
            return String(localized: "About \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) · \(quality.useCase)")
        }
        if session.isEstimating {
            return String(localized: "Estimating size… · \(quality.useCase)")
        }
        return String(localized: "Usually \(quality.expectedReduction) smaller · \(quality.useCase)")
    }

    private var customRow: some View {
        Button {
            let toggle = {
                withAnimation {
                    session.choice = session.choice == .custom ? .preset(appState.defaultQuality) : .custom
                }
            }
            if appState.requirePro(.customQuality, then: { session.choice = .custom }) {
                toggle()
            }
        } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: "slider.horizontal.3", color: .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom")
                    Text("Set image quality and resolution")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appState.isPro {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(session.choice == .custom ? 90 : 0))
                } else {
                    ProBadge()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(session.choice == .custom ? .isSelected : [])
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Image quality") {
                Text("\(Int(session.imageQuality))%").monospacedDigit()
            }
            Slider(value: $session.imageQuality, in: 20...95, step: 5)
                .accessibilityLabel("Image quality")
            LabeledContent("Resolution") {
                Text("\(Int(session.resolution)) dpi").monospacedDigit()
            }
            .padding(.top, 6)
            Slider(value: $session.resolution, in: 72...300, step: 6)
                .accessibilityLabel("Resolution")
            Text("Lower values make smaller files. Text stays sharp; only images lose detail.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Working

    private var workingView: some View {
        let batch = appState.batchProgress
        let detail: String
        let progress: Double?
        if session.isBatch, let batch, batch.total > 0 {
            detail = String(localized: "\(batch.done) of \(batch.total) PDFs")
            progress = Double(batch.done) / Double(batch.total)
        } else {
            detail = session.documents.first?.name ?? ""
            progress = nil
        }
        return WorkingView(title: String(localized: "Compressing…"), detail: detail, progress: progress)
            .background(Color.groupedBackground)
            .bottomActions {
                Button {
                    appState.cancelCompression(session)
                } label: {
                    ActionLabel(title: String(localized: "Cancel"))
                }
                .secondaryButtonStyle()
                .keyboardShortcut(.cancelAction)
            }
    }
}

// MARK: - Quality row

private struct QualityRow: View {
    let quality: CompressionQuality
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(quality.title)
                        if quality == .medium {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Result

private struct CompressResultView: View {
    let session: CompressSession
    @Environment(AppState.self) private var appState

    private var urls: [URL] { session.results.map(\.outputURL) }

    var body: some View {
        List {
            Section {
                header
                bars
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

            Section {
                SaveToFilesButton(urls: urls)
                if session.results.count == 1, let result = session.results.first {
                    Button {
                        appState.homePath.append(.preview(FileItem(result)))
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                }
                if session.results.count == 1, let result = session.results.first {
                    Button {
                        appState.showToolPicker(for: FileItem(result))
                    } label: {
                        Label("Continue with Another Tool", systemImage: "arrow.right")
                    }
                }
                Button {
                    appState.closeTask()
                    appState.chooseFilesToCompress()
                } label: {
                    Label("Compress Another", systemImage: "arrow.down.doc")
                }
            } footer: {
                if !appState.isPro {
                    HStack(spacing: 4) {
                        Text("\(appState.usage.remaining) free actions left today.")
                        Button("Go unlimited") { appState.showPaywall(.general) }
                            .font(.footnote.weight(.semibold))
                    }
                }
            }

            if session.results.count > 1 {
                Section("Files") {
                    ForEach(session.results) { result in
                        let item = FileItem(result)
                        Button {
                            appState.homePath.append(.preview(item))
                        } label: {
                            FileRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .bottomActions {
            ShareLink(items: urls) {
                ActionLabel(title: String(localized: "Share"), systemImage: "square.and.arrow.up")
            }
            .primaryButtonStyle()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { appState.closeTask() }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        let percent = session.reductionPercent
        let name = session.results.count == 1 ? FileItem(session.results[0]).name : "\(session.results.count) PDFs compressed"
        if percent > 0 {
            ResultHeader(headline: String(localized: "\(percent)% smaller"), detail: name)
        } else {
            ResultHeader(headline: String(localized: "Already small"), detail: String(localized: "\(name) was already well optimized, so there was little to remove."))
        }
    }

    private var bars: some View {
        let original = session.originalTotal
        let compressed = session.compressedTotal
        let fraction = original > 0 ? min(1, Double(compressed) / Double(original)) : 1
        return VStack(spacing: 10) {
            SizeBar(label: "Before", bytes: original, fraction: 1, color: Color.secondary.opacity(0.35))
            SizeBar(label: "After", bytes: compressed, fraction: max(0.03, fraction), color: .accentColor)
        }
        .cardStyle()
    }
}

private struct SizeBar: View {
    let label: String
    let bytes: Int64
    let fraction: Double
    let color: Color

    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: proxy.size.width * (shown ? fraction : 1))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) { shown = true }
        }
    }
}
