//
//  AppState.swift
//  Mino
//
//  Global application state
//

import Foundation
import SwiftUI

/// Global application state observable
@Observable
@MainActor
final class AppState {

    // MARK: - Services

    /// Document import service
    let documentImporter = DocumentImporter()

    /// Compression service
    let compressionService = CompressionService()

    /// Export service
    let exportService = ExportService()

    /// Merge service
    let mergeService = MergeService()

    /// Split service
    let splitService = SplitService()

    /// Batch compression service
    let batchCompressionService = BatchCompressionService()

    // MARK: - Document State

    /// List of imported documents
    var importedDocuments: [PDFDocumentInfo] = []

    /// Currently selected document for compression (single file)
    var selectedDocument: PDFDocumentInfo?

    /// Documents to compress (unified for single and batch)
    var documentsToCompress: [PDFDocumentInfo] = []

    /// Selected compression quality
    var selectedQuality: CompressionQuality = .medium

    // MARK: - Navigation State

    /// Whether the document picker is showing
    var showingDocumentPicker = false

    /// Whether the compression view is showing
    var showingCompressionView = false

    /// Whether the results view is showing (single file)
    var showingResultsView = false

    /// Whether the batch results view is showing
    var showingBatchResultsView = false

    /// The current compression result to display (single file)
    var currentResult: CompressionResult?

    // MARK: - Tools Navigation State

    /// Whether the merge view is showing
    var showingMergeView = false

    /// Whether the split view is showing
    var showingSplitView = false

    /// Whether the batch compression view is showing
    var showingBatchCompressionView = false

    /// Whether showing document picker for split
    var showingDocumentPickerForSplit = false

    /// Whether showing multi-document picker (for batch or merge)
    var showingMultiDocumentPicker = false

    // MARK: - Tools Data State

    /// Document selected for splitting
    var documentForSplit: PDFDocumentInfo?

    /// Documents selected for batch compression
    var documentsForBatchCompression: [PDFDocumentInfo] = []

    // MARK: - Error Handling

    /// Current error to display
    var currentError: Error?

    /// Whether to show error alert
    var showingError = false

    // MARK: - Methods

    /// Shows an error to the user
    func showError(_ error: Error) {
        currentError = error
        showingError = true
    }

    /// Clears the current error
    func clearError() {
        currentError = nil
        showingError = false
    }

    /// Adds a document to the imported list
    func addImportedDocument(_ document: PDFDocumentInfo) {
        // Remove if already exists (update)
        importedDocuments.removeAll { $0.url == document.url }
        // Add to beginning
        importedDocuments.insert(document, at: 0)
    }

    /// Removes a document from the imported list
    func removeImportedDocument(_ document: PDFDocumentInfo) {
        importedDocuments.removeAll { $0.id == document.id }
        try? documentImporter.deleteDocument(document)
    }

    /// Starts compression for a document
    func startCompression(for document: PDFDocumentInfo) {
        selectedDocument = document
        showingCompressionView = true
    }

    /// Shows results for a compression
    func showResults(_ result: CompressionResult) {
        currentResult = result
        showingResultsView = true

        // Track in history
        if let document = selectedDocument {
            HistoryManager.shared.addEntry(from: result, originalFileName: document.name)
        }
    }

    /// Shows results for batch compression
    func showBatchResults(_ results: [CompressionResult]) {
        // Track all in history
        for (index, result) in results.enumerated() {
            if index < documentsToCompress.count {
                HistoryManager.shared.addEntry(from: result, originalFileName: documentsToCompress[index].name)
            }
        }

        // Show the batch results view
        showingBatchResultsView = true
    }

    /// Starts compression for documents (single or batch)
    func startCompressionForDocuments(_ documents: [PDFDocumentInfo]) {
        documentsToCompress = documents
        showingCompressionView = true
    }
}
