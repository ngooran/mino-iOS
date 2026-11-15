//
//  PhotosToPDFFlowView.swift
//  Mino
//
//  Pick photos → reorder → page size and margins → Create PDF.
//

import PhotosUI
import SwiftUI

struct PhotosToPDFFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.photosSession {
            PhotosToPDFContent(session: session)
        } else {
            NoSessionView(tool: .photosToPDF)
        }
    }
}

private struct PhotosToPDFContent: View {
    @Bindable var session: PhotosToPDFSession
    @Environment(AppState.self) private var appState
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        ToolFlow(
            tool: .photosToPDF,
            state: session.state,
            workingTitle: String(localized: "Creating your PDF…"),
            workingDetail: String(localized: "\(session.photos.count) photos"),
            resultHeadline: String(localized: "PDF created")
        ) {
            configureView
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
        if session.photos.isEmpty {
            ContentUnavailableView {
                Label("Add Photos", systemImage: "photo.on.rectangle")
            } description: {
                Text("Choose JPG, PNG or HEIC images. Each one becomes a page.")
            } actions: {
                if session.isLoading {
                    ProgressView()
                } else {
                    PhotosPicker(selection: $pickerItems, matching: .images, preferredItemEncoding: .current) {
                        Text("Choose Photos")
                    }
                    .secondaryButtonStyle()
                    Button("Choose from Files") { appState.importTarget = .tool(.photosToPDF) }
                }
            }
            .background(Color.groupedBackground)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 8)], spacing: 8) {
                        ForEach(Array(session.photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoCell(photo: photo, number: index + 1) {
                                withAnimation { session.photos.removeAll { $0.id == photo.id } }
                            }
                            .draggable(photo.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                                withAnimation { session.move(dragged, to: photo.id) }
                                return true
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $pickerItems, matching: .images, preferredItemEncoding: .current) {
                            Label("Add Photos", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            appState.importTarget = .tool(.photosToPDF)
                        } label: {
                            Label("From Files", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(session.isLoading)

                    if session.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Adding photos…").foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                    }

                    OptionLabel(String(localized: "Page Size"))
                    Picker("Page Size", selection: $session.pageSize) {
                        ForEach(PhotoPageSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    OptionLabel(String(localized: "Margins"))
                    Picker("Margins", selection: $session.margin) {
                        ForEach(PhotoMargin.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text("Drag photos to change their order. JPEG photos go in untouched, so they lose no quality.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Color.groupedBackground)
            .bottomActions {
                Button {
                    appState.createPDF(session)
                } label: {
                    ToolActionLabel(title: String(localized: "Create PDF (\(session.photos.count) pages)"), tool: .photosToPDF)
                }
                .primaryButtonStyle()
                .disabled(session.isLoading)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Copies the picked photos into the working folder, in their original format.
    private func load(_ items: [PhotosPickerItem]) async {
        session.isLoading = true
        defer { session.isLoading = false }
        let folder = OutputLocation.workingDirectory()
        var urls: [URL] = []
        var failed = 0
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failed += 1
                continue
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = folder.appendingPathComponent("photo-\(index).\(ext)")
            if (try? data.write(to: url)) != nil {
                urls.append(url)
            } else {
                failed += 1
            }
        }
        await appState.addPhotoFiles(urls)
        if failed > 0 {
            appState.errorMessage = String(localized: "\(failed) photos couldn't be loaded.")
        }
    }
}

private struct PhotoCell: View {
    let photo: PhotoInput
    let number: Int
    let remove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: "\(number)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
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
                .accessibilityLabel("Remove photo \(number)")
            }
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo \(number)")
            .task(id: photo.id) {
                let url = photo.url
                image = await Task.detached(priority: .utility) { ImageThumbnail.make(url: url, maxPixel: 360) }.value
            }
    }
}

/// Downsampled, upright thumbnails of image files.
nonisolated enum ImageThumbnail {
    static func make(url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
