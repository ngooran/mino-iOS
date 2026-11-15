//
//  PDFToImagesFlowView.swift
//  Mino
//
//  Open PDF → choose pages → JPG or PNG, 150 or 300 dpi → Export.
//

import Photos
import SwiftUI

struct PDFToImagesFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.imagesSession {
            PDFToImagesContent(session: session)
                .id(session.document.id)
        } else {
            NoSessionView(tool: .pdfToImages)
        }
    }
}

private struct PDFToImagesContent: View {
    @Bindable var session: PDFToImagesSession
    @Environment(AppState.self) private var appState
    @State private var loader: PageThumbnailLoader

    init(session: PDFToImagesSession) {
        self.session = session
        _loader = State(initialValue: PageThumbnailLoader(url: session.document.url))
    }

    var body: some View {
        ToolFlow(
            tool: .pdfToImages,
            state: session.state,
            workingTitle: String(localized: "Exporting…"),
            workingDetail: session.document.name,
            resultHeadline: String(localized: "Images ready")
        ) {
            configureView
        } extras: { item in
            ImageStrip(urls: Array(item.urls.prefix(6)))
        }
    }

    private var configureView: some View {
        let count = session.pages.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DocumentCard(document: session.document) { appState.importTarget = .tool(.pdfToImages) }
                    .cardStyle()

                OptionLabel(String(localized: "Pages"))
                Picker("Pages", selection: $session.scope) {
                    Text("All \(session.document.pageCount) Pages").tag(PDFToImagesSession.Scope.all)
                    Text("Choose Pages").tag(PDFToImagesSession.Scope.choose)
                }
                .pickerStyle(.segmented)

                if session.scope == .choose {
                    PageSelectionGrid(loader: loader, pageCount: session.document.pageCount, selection: $session.selectedPages)
                        .padding(.top, 4)
                }

                OptionLabel(String(localized: "Format"))
                Picker("Format", selection: $session.format) {
                    ForEach(ImageFormat.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                OptionLabel(String(localized: "Resolution"))
                Picker("Resolution", selection: $session.resolution) {
                    ForEach(ImageResolution.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(session.format == .jpg
                     ? String(localized: "JPG makes small files and suits photos and scans.")
                     : String(localized: "PNG keeps text and lines perfectly sharp, in larger files."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Color.groupedBackground)
        .bottomActions {
            Button {
                appState.exportImages(session)
            } label: {
                ToolActionLabel(title: String(localized: "Export \(count) Images"), tool: .pdfToImages)
            }
            .primaryButtonStyle()
            .disabled(count == 0)
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// The first few exported images, side by side.
private struct ImageStrip: View {
    let urls: [URL]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(urls, id: \.self) { url in
                StripImage(url: url)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 76)
        .cardStyle(padding: 12)
        .accessibilityHidden(true)
    }
}

private struct StripImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white.aspectRatio(0.77, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) { ImageThumbnail.make(url: url, maxPixel: 240) }.value
        }
    }
}

// MARK: - Save to Photos

/// Adds exported images to the photo library. Asks for add-only access.
struct SaveToPhotosButton: View {
    let urls: [URL]

    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                Label("Save to Photos", systemImage: "photo.on.rectangle")
                Spacer()
                if isSaving { ProgressView() }
            }
        }
        .disabled(isSaving)
        .alert("Save to Photos", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = String(localized: "Mino isn't allowed to add to Photos. You can change this in Settings.")
            return
        }
        let files = urls
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in files {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                }
            }
            message = String(localized: "\(files.count) images saved to Photos.")
            HapticManager.shared.compressionComplete()
        } catch {
            message = error.localizedDescription
        }
    }
}
