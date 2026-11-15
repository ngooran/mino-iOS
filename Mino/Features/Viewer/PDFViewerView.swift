//
//  PDFViewerView.swift
//  Mino
//
//  PDF viewer using QuickLook for reliable document preview
//

import SwiftUI
import QuickLook

// MARK: - Main PDF Viewer View

struct PDFViewerView: View {
    @Environment(\.dismiss) private var dismiss
    let documentURL: URL

    var body: some View {
        NavigationStack {
            QuickLookPreview(urls: [documentURL.standardizedFileURL])
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(documentURL.deletingPathExtension().lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - QuickLook Preview (UIViewControllerRepresentable)

struct QuickLookPreview: UIViewControllerRepresentable {
    /// One file, or several to page through (the images of a PDF to Images export).
    let urls: [URL]

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Don't reload - it can cause issues
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: QuickLookPreview

        init(_ parent: QuickLookPreview) {
            self.parent = parent
        }

        // MARK: - QLPreviewControllerDataSource

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            existingURLs.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return PreviewItem(url: existingURLs[index])
        }

        /// Files that are still on disk.
        private var existingURLs: [URL] {
            parent.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
}

// MARK: - Preview Item

class PreviewItem: NSObject, QLPreviewItem {
    let fileURL: URL

    init(url: URL) {
        self.fileURL = url
        super.init()
    }

    var previewItemURL: URL? {
        return fileURL
    }

    var previewItemTitle: String? {
        return fileURL.deletingPathExtension().lastPathComponent
    }
}

#Preview {
    PDFViewerView(documentURL: URL(fileURLWithPath: "/test.pdf"))
}
