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
    /// The copy at `url` needs a password before it can be used.
    case passwordRequired(copy: URL)
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return String(localized: "Cannot access the selected file")
        case .coordinationFailed(let error):
            return String(localized: "File access failed: \(error.localizedDescription)")
        case .copyFailed(let error):
            return String(localized: "Failed to copy file: \(error.localizedDescription)")
        case .invalidPDF(let error):
            return String(localized: "Invalid PDF: \(error.localizedDescription)")
        case .fileNotFound:
            return String(localized: "File not found")
        case .passwordRequired:
            return String(localized: "This PDF needs a password")
        case .wrongPassword:
            return String(localized: "That password didn't work")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accessDenied:
            return String(localized: "Try selecting the file again")
        case .coordinationFailed, .copyFailed:
            return String(localized: "Make sure the file is not in use by another app")
        case .invalidPDF:
            return String(localized: "Please select a valid PDF file")
        case .fileNotFound:
            return String(localized: "The file may have been moved or deleted")
        case .passwordRequired, .wrongPassword:
            return String(localized: "Enter the password that opens the PDF")
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
        let documentsDir = StorageRoot.documents
        return documentsDir.appendingPathComponent(OutputLocation.workingFolder, isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        // Imported copies are only inputs for the current session.
        // Clear copies left over from earlier launches, then recreate the folder.
        try? fileManager.removeItem(at: importedPDFsDirectory)
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

        return try inspect(copy: destinationURL)
    }

    /// Opens the working copy and reads its page count. Throws
    /// `passwordRequired` when it is locked; the copy then stays in place so
    /// `unlock(copy:password:)` can finish the import.
    private func inspect(copy destinationURL: URL) throws -> PDFDocumentInfo {
        guard let ctx = mino_create_context() else {
            try? fileManager.removeItem(at: destinationURL)
            throw ImportError.invalidPDF(MuPDFError.contextCreationFailed)
        }
        defer { mino_drop_context(ctx) }
        guard let doc = mino_open_document(ctx, destinationURL.path) else {
            let reason = mino_get_last_error().map { String(cString: $0) }
            try? fileManager.removeItem(at: destinationURL)
            throw ImportError.invalidPDF(MuPDFError.documentOpenFailed(path: destinationURL.path, reason: reason))
        }
        defer { mino_drop_document(ctx, doc) }
        guard let pdf = mino_pdf_specifics(ctx, doc) else {
            try? fileManager.removeItem(at: destinationURL)
            throw ImportError.invalidPDF(MuPDFError.invalidPDFDocument)
        }
        if mino_needs_password(ctx, doc) != 0 {
            throw ImportError.passwordRequired(copy: destinationURL)
        }
        let pageCount = Int(mino_count_pages(ctx, doc))
        guard pageCount > 0 else {
            try? fileManager.removeItem(at: destinationURL)
            throw ImportError.invalidPDF(MuPDFError.invalidPDFDocument)
        }
        var info = PDFDocumentInfo(url: destinationURL, pageCount: pageCount)
        info.hasRestrictions = mino_is_encrypted(ctx, pdf) != 0
        return info
    }

    /// Finishes importing a locked PDF: checks the password and replaces the
    /// working copy with an unlocked one, so every tool can read it.
    /// - Throws: `ImportError.wrongPassword` when the password is not accepted.
    func unlock(copy: URL, password: String) async throws -> PDFDocumentInfo {
        let unlocked = copy.deletingLastPathComponent().appendingPathComponent("unlocked-\(UUID().uuidString).pdf")
        let pageCount = try await Task.detached(priority: .userInitiated) {
            try DocumentImporter.writeUnlockedCopy(of: copy, password: password, to: unlocked)
        }.value
        try? fileManager.removeItem(at: copy)
        try fileManager.moveItem(at: unlocked, to: copy)
        var info = PDFDocumentInfo(url: copy, pageCount: pageCount)
        info.wasLocked = true
        return info
    }

    /// Drops a locked copy the person chose not to unlock.
    func discard(copy: URL) {
        try? fileManager.removeItem(at: copy)
    }

    /// Returns the page count of the unlocked copy.
    nonisolated static func writeUnlockedCopy(of source: URL, password: String, to destination: URL) throws -> Int {
        guard let ctx = mino_create_context() else { throw MuPDFError.contextCreationFailed }
        defer { mino_drop_context(ctx) }
        guard let doc = mino_open_document(ctx, source.path) else {
            throw MuPDFError.documentOpenFailed(path: source.path, reason: nil)
        }
        defer { mino_drop_document(ctx, doc) }
        guard MuPDF.authenticate(ctx, doc, password: password) != 0 else { throw ImportError.wrongPassword }
        guard let pdf = mino_pdf_specifics(ctx, doc) else { throw MuPDFError.invalidPDFDocument }
        guard mino_save_decrypted(ctx, pdf, destination.path) == 0 else {
            throw MuPDFError.saveFailed(reason: mino_get_last_error().map { String(cString: $0) } ?? "Unknown error")
        }
        return Int(mino_count_pages(ctx, doc))
    }

    /// Copies any file (an image, an Office document) into the working folder
    /// and returns the copy.
    func importFile(from sourceURL: URL) async throws -> URL {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let name = OutputLocation.sanitized(sourceURL.deletingPathExtension().lastPathComponent)
        let folder = importedPDFsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(name)
        if !sourceURL.pathExtension.isEmpty {
            destination = destination.appendingPathExtension(sourceURL.pathExtension)
        }
        try await copyFileWithCoordination(from: sourceURL, to: destination)
        return destination
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
        // Each import gets its own folder so the copy keeps its original name.
        let originalName = OutputLocation.sanitized(sourceURL.deletingPathExtension().lastPathComponent)
        let folder = importedPDFsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(originalName).appendingPathExtension("pdf")
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
