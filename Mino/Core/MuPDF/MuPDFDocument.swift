//
//  MuPDFDocument.swift
//  Mino
//
//  Swift wrapper for MuPDF document operations
//

import Foundation

/// Wrapper for MuPDF document providing Swift-friendly interface
final class MuPDFDocument: @unchecked Sendable {

    // MARK: - Properties

    /// The source file URL
    let sourceURL: URL

    /// Number of pages in the document
    private(set) var pageCount: Int = 0

    /// Original file size in bytes
    private(set) var originalFileSize: Int64 = 0

    /// Internal MuPDF context pointer
    private var context: UnsafeMutablePointer<fz_context>?

    /// Internal document pointer
    private var document: UnsafeMutablePointer<fz_document>?

    /// Internal PDF document pointer
    private var pdfDocument: UnsafeMutablePointer<pdf_document>?

    /// Lock for thread safety
    private let lock = NSLock()

    // MARK: - Initialization

    /// Opens a PDF document from the specified URL
    /// - Parameter url: The file URL of the PDF document
    /// - Throws: MuPDFError if the document cannot be opened
    init(url: URL) throws {
        self.sourceURL = url

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MuPDFError.fileNotFound(path: url.path)
        }

        // Get original file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            self.originalFileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            throw MuPDFError.accessDenied(path: url.path)
        }

        // Create MuPDF context
        guard let ctx = mino_create_context() else {
            throw MuPDFError.contextCreationFailed
        }
        self.context = ctx

        // Open document
        guard let doc = mino_open_document(ctx, url.path) else {
            let errorMsg = String(cString: mino_get_last_error() ?? "Unknown error".withCString { $0 })
            mino_drop_context(ctx)
            throw MuPDFError.documentOpenFailed(path: url.path, reason: errorMsg)
        }
        self.document = doc

        // Get PDF-specific handle
        guard let pdfDoc = mino_pdf_specifics(ctx, doc) else {
            mino_drop_document(ctx, doc)
            mino_drop_context(ctx)
            throw MuPDFError.invalidPDFDocument
        }
        self.pdfDocument = pdfDoc

        // Get page count
        let count = mino_count_pages(ctx, doc)
        if count < 0 {
            mino_drop_document(ctx, doc)
            mino_drop_context(ctx)
            throw MuPDFError.invalidPDFDocument
        }
        self.pageCount = Int(count)
    }

    deinit {
        close()
    }

    // MARK: - Public Methods

    /// Closes the document and releases resources
    func close() {
        lock.lock()
        defer { lock.unlock() }

        if let ctx = context {
            if let doc = document {
                mino_drop_document(ctx, doc)
                document = nil
                pdfDocument = nil
            }
            mino_drop_context(ctx)
            context = nil
        }
    }

    /// Returns the internal context pointer (for advanced operations)
    func getContext() -> UnsafeMutablePointer<fz_context>? {
        lock.lock()
        defer { lock.unlock() }
        return context
    }

    /// Returns the internal PDF document pointer (for advanced operations)
    func getPDFDocument() -> UnsafeMutablePointer<pdf_document>? {
        lock.lock()
        defer { lock.unlock() }
        return pdfDocument
    }

    /// Checks if the document is still open
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return context != nil && document != nil
    }

    /// Gets the filename without extension
    var fileName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    /// Gets formatted file size string
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: originalFileSize, countStyle: .file)
    }
}

// MARK: - CustomStringConvertible

extension MuPDFDocument: CustomStringConvertible {
    var description: String {
        "MuPDFDocument(\(fileName), \(pageCount) pages, \(formattedFileSize))"
    }
}
