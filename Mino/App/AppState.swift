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

    // MARK: - Document State

    /// List of imported documents
    var importedDocuments: [PDFDocumentInfo] = []

    /// Currently selected document for compression
    var selectedDocument: PDFDocumentInfo?

    /// Selected compression quality
    var selectedQuality: CompressionQuality = .medium

    // MARK: - Navigation State

    /// Whether the document picker is showing
    var showingDocumentPicker = false

    /// Whether the compression view is showing
    var showingCompressionView = false

    /// Whether the results view is showing
    var showingResultsView = false

    /// The current compression result to display
    var currentResult: CompressionResult?

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
}
