//
//  ExportService.swift
//  Mino
//
//  Service for exporting compressed PDFs
//

import SwiftUI
import UniformTypeIdentifiers

/// Service for exporting and sharing compressed PDFs
@Observable
@MainActor
final class ExportService {

    // MARK: - Properties

    /// Whether an export is in progress
    var isExporting = false

    /// The most recent export error
    var exportError: Error?

    // MARK: - Sharing

    /// Gets the URL for sharing a compression result
    func shareURL(for result: CompressionResult) -> URL {
        return result.outputURL
    }

    /// Gets share items for a compression result
    func shareItems(for result: CompressionResult) -> [Any] {
        return [result.outputURL]
    }

    // MARK: - File Export

    /// Saves a compressed PDF to a user-selected location
    func saveToFiles(result: CompressionResult) -> URL {
        return result.outputURL
    }

    /// Copies the compressed PDF to a new location
    func copyToLocation(_ result: CompressionResult, destination: URL) throws {
        isExporting = true
        exportError = nil

        defer { isExporting = false }

        do {
            // Remove existing file at destination if present
            try? FileManager.default.removeItem(at: destination)

            // Copy file
            try FileManager.default.copyItem(at: result.outputURL, to: destination)
        } catch {
            exportError = error
            throw error
        }
    }
}

// MARK: - Share Sheet

/// SwiftUI wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Document Export Picker

/// SwiftUI wrapper for exporting documents
struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentExporter

        init(_ parent: DocumentExporter) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onComplete?(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onComplete?(false)
        }
    }
}
