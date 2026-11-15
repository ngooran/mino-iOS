//
//  ScanFlowView.swift
//  Mino
//
//  Camera → add pages → review (reorder, delete, retake, filter) → Save PDF.
//

import PhotosUI
import SwiftUI

struct ScanFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.scanSession {
            ScanContent(session: session)
        } else {
            NoSessionView(tool: .scan)
        }
    }
}

private struct ScanContent: View {
    @Bindable var session: ScanSession
    @Environment(AppState.self) private var appState
    @State private var camera: CameraRequest?
    @State private var pickerItems: [PhotosPickerItem] = []

    /// Why the camera is open: more pages, or a new capture of one page.
    private struct CameraRequest: Identifiable {
        let id = UUID()
        var retake: ScanPage.ID?
    }

    var body: some View {
        ToolFlow(
            tool: .scan,
            state: session.state,
            workingTitle: String(localized: "Building your PDF…"),
            workingDetail: String(localized: "\(session.pages.count) pages"),
            resultHeadline: String(localized: "Scan saved")
        ) {
            configureView
        } extras: { _ in
            RecognizedTextCard(text: session.state.resultText)
        }
        .fullScreenCover(item: $camera) { request in
            DocumentCamera { images in
                camera = nil
                Task { await appState.addScannedImages(images, replacing: request.retake) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await load(items) }
        }
    }

    // MARK: - Configure

    @ViewBuilder
    private var configureView: some View {
        if session.pages.isEmpty {
            emptyView
        } else {
            reviewView
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Scan a Document", systemImage: "doc.viewfinder")
        } description: {
            Text(DocumentCamera.isSupported
                 ? "Hold your \(deviceName) over the page. Mino finds the edges and captures it."
                 : "The document camera isn't available on this device. You can use photos of your pages instead.")
        } actions: {
            if session.isLoading {
                ProgressView()
            } else {
                if DocumentCamera.isSupported {
                    Button("Start Scanning") { camera = CameraRequest() }
                        .secondaryButtonStyle()
                }
                PhotosPicker(selection: $pickerItems, matching: .images, preferredItemEncoding: .current) {
                    Text("Choose Photos")
                }
                #if DEBUG
                // The document camera can't run in the simulator.
                Button("Use Sample Pages") { appState.addScanFiles(DebugLaunch.makeSampleScanPages(count: 3)) }
                #endif
            }
        }
        .background(Color.groupedBackground)
        .task {
            // Straight to the camera, as the Scan button promises.
            if DocumentCamera.isSupported && session.pages.isEmpty && camera == nil && !StorageRoot.isDemo {
                camera = CameraRequest()
            }
        }
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 12)], spacing: 14) {
                    ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
                        ScanPageCell(page: page, number: index + 1, filter: session.filter) {
                            withAnimation { session.pages.removeAll { $0.id == page.id } }
                        }
                        .draggable(page.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            withAnimation { session.move(dragged, to: page.id) }
                            return true
                        }
                        .contextMenu {
                            if DocumentCamera.isSupported {
                                Button {
                                    camera = CameraRequest(retake: page.id)
                                } label: {
                                    Label("Retake", systemImage: "camera")
                                }
                            }
                            Button(role: .destructive) {
                                withAnimation { session.pages.removeAll { $0.id == page.id } }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    addCell
                }

                OptionLabel(String(localized: "Filter"))
                Picker("Filter", selection: $session.filter) {
                    ForEach(ScanFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if Tool.ocr.isAvailable {
                    Toggle(isOn: $session.makeSearchable) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Make Text Searchable")
                                Text("Recognize text so you can search and copy it")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if !appState.isPro { ProBadge() }
                        }
                    }
                    .cardStyle(padding: 14, cornerRadius: 22)
                }

                Text("Drag pages to change their order. Touch and hold a page to retake or delete it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Color.groupedBackground)
        .bottomActions {
            Button {
                appState.saveScan(session)
            } label: {
                ToolActionLabel(
                    title: String(localized: "Save PDF (\(session.pages.count) pages)"),
                    tool: .scan,
                    needsPro: session.makeSearchable
                )
            }
            .primaryButtonStyle()
            .disabled(session.isLoading)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// "Add": the camera where there is one, otherwise the photo picker.
    @ViewBuilder
    private var addCell: some View {
        let label = VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .aspectRatio(0.72, contentMode: .fit)
                .overlay {
                    if session.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            Text("Add")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())

        if DocumentCamera.isSupported {
            Button { camera = CameraRequest() } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Add pages")
        } else {
            PhotosPicker(selection: $pickerItems, matching: .images, preferredItemEncoding: .current) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Add pages")
        }
    }

    /// Copies picked photos into the working folder and adds them as pages.
    private func load(_ items: [PhotosPickerItem]) async {
        session.isLoading = true
        defer { session.isLoading = false }
        let folder = OutputLocation.workingDirectory()
        var urls: [URL] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = folder.appendingPathComponent("page-\(index).\(ext)")
            if (try? data.write(to: url)) != nil { urls.append(url) }
        }
        appState.addScanFiles(urls)
        if urls.count < items.count {
            appState.errorMessage = String(localized: "\(items.count - urls.count) photos couldn't be loaded.")
        }
    }
}

/// One scanned page with the chosen filter applied, as it will be saved.
private struct ScanPageCell: View {
    let page: ScanPage
    let number: Int
    let filter: ScanFilter
    let remove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.white
                        .aspectRatio(0.72, contentMode: .fit)
                        .overlay { ProgressView().controlSize(.small).tint(.gray) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove page \(number)")
            }
            Text(verbatim: "\(number)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(number)")
        .task(id: "\(page.url.path)-\(filter.rawValue)") {
            let url = page.url
            let filter = filter
            image = await Task.detached(priority: .utility) {
                ScanEngine.filteredImage(from: url, filter: filter, maxPixel: 420).map { UIImage(cgImage: $0) }
            }.value
        }
    }
}

/// Recognized text on a result screen, with a Copy button. Hidden when there is none.
struct RecognizedTextCard: View {
    let text: String?
    @State private var copied = false

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    HapticManager.shared.selectionChanged()
                } label: {
                    Label(copied ? "Copied" : "Copy Text", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .cardStyle()
        }
    }
}
