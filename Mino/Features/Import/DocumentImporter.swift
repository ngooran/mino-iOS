//
//  DocumentImporter.swift
//  Mino
//
//  Handles PDF document import from various sources
//

import Foundation
import UniformTypeIdentifiers

/// Errors that can occur during document import
enum ImportError: Error, LocalizedError {
    case accessDenied
    case coordinationFailed(Error)
    case copyFailed(Error)
    case invalidPDF(Error)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access the selected file"
        case .coordinationFailed(let error):
            return "File access failed: \(error.localizedDescription)"
        case .copyFailed(let error):
            return "Failed to copy file: \(error.localizedDescription)"
        case .invalidPDF(let error):
            return "Invalid PDF: \(error.localizedDescription)"
        case .fileNotFound:
            return "File not found"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accessDenied:
            return "Try selecting the file again"
        case .coordinationFailed, .copyFailed:
            return "Make sure the file is not in use by another app"
        case .invalidPDF:
            return "Please select a valid PDF file"
        case .fileNotFound:
            return "The file may have been moved or deleted"
        }
    }
}

/// Handles importing PDF documents into the app
@Observable
@MainActor
final class DocumentImporter {

    // MARK: - Properties

    /// Whether an import is in progress
    var isImporting = false

    /// The most recent import error
    var importError: Error?

    /// File manager instance
    private let fileManager = FileManager.default

    /// Directory for storing imported PDFs
    private var importedPDFsDirectory: URL {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("ImportedPDFs", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        // Create import directory if needed
        try? fileManager.createDirectory(
            at: importedPDFsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Import Methods

    /// Imports a PDF document from a URL
    /// - Parameter sourceURL: The URL of the PDF to import
    /// - Returns: Document info for the imported PDF
    /// - Throws: ImportError if import fails
    func importDocument(from sourceURL: URL) async throws -> PDFDocumentInfo {
        isImporting = true
        importError = nil

        defer { isImporting = false }

        // Start security-scoped access
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Create unique destination filename
        let destinationURL = generateDestinationURL(for: sourceURL)

        // Copy file with coordination
        try await copyFileWithCoordination(from: sourceURL, to: destinationURL)

        // Validate and open with MuPDF
        do {
            let muDocument = try MuPDFDocument(url: destinationURL)
            let documentInfo = PDFDocumentInfo(from: muDocument)
            muDocument.close()
            return documentInfo
        } catch {
            // Clean up copied file on failure
            try? fileManager.removeItem(at: destinationURL)
            throw ImportError.invalidPDF(error)
        }
    }

    /// Imports a PDF from data (e.g., from drag and drop)
    /// - Parameters:
    ///   - data: The PDF data
    ///   - suggestedName: A suggested filename
    /// - Returns: Document info for the imported PDF
    func importDocument(data: Data, suggestedName: String) async throws -> PDFDocumentInfo {
        isImporting = true
        importError = nil

        defer { isImporting = false }

        // Generate unique filename
        _ = suggestedName.hasSuffix(".pdf") ? suggestedName : "\(suggestedName).pdf"
        let destinationURL = importedPDFsDirectory
            .appendingPathComponent(UUID().uuidString)
            .deletingPathExtension()
            .appendingPathExtension("pdf")

        // Write data to file
        do {
            try data.write(to: destinationURL)
        } catch {
            throw ImportError.copyFailed(error)
        }

        // Validate and open with MuPDF
        do {
            let muDocument = try MuPDFDocument(url: destinationURL)
            let documentInfo = PDFDocumentInfo(from: muDocument)
            muDocument.close()
            return documentInfo
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw ImportError.invalidPDF(error)
        }
    }

    // MARK: - Private Methods

    /// Generates a unique destination URL for an imported file
    private func generateDestinationURL(for sourceURL: URL) -> URL {
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let uniqueID = UUID().uuidString.prefix(8)
        let filename = "\(originalName)_\(uniqueID).pdf"
        return importedPDFsDirectory.appendingPathComponent(filename)
    }

    /// Copies a file using file coordination for safe access
    private func copyFileWithCoordination(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(
                readingItemAt: source,
                options: [],
                error: &coordinatorError
            ) { coordinatedURL in
                do {
                    // Remove destination if it exists
                    try? self.fileManager.removeItem(at: destination)
                    try self.fileManager.copyItem(at: coordinatedURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: ImportError.copyFailed(error))
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: ImportError.coordinationFailed(error))
            }
        }
    }

    /// Deletes an imported document
    func deleteDocument(_ document: PDFDocumentInfo) throws {
        try fileManager.removeItem(at: document.url)
    }

    /// Lists all imported documents
    func listImportedDocuments() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: importedPDFsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return date1 > date2
            }
    }
}
