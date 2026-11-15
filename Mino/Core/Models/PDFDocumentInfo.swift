//
//  PDFDocumentInfo.swift
//  Mino
//
//  Data model representing a PDF document
//

import Foundation
import SwiftUI

/// Information about a PDF document in the app
struct PDFDocumentInfo: Identifiable, Equatable, Sendable {

    // MARK: - Properties

    /// Unique identifier
    let id: UUID

    /// File URL
    let url: URL

    /// Display name (filename without extension)
    let name: String

    /// File size in bytes
    let fileSize: Int64

    /// Number of pages
    let pageCount: Int

    /// When the document was imported
    let importDate: Date

    /// The original needed a password to open. `url` is an unlocked working copy.
    var wasLocked = false

    /// The file is encrypted to restrict printing or copying, but opens without a password.
    var hasRestrictions = false

    // MARK: - Computed Properties

    /// Formatted file size (e.g., "12.5 MB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Formatted page count
    var formattedPageCount: String {
        String(localized: "\(pageCount) pages")
    }

    /// Short description for list display
    var shortDescription: String {
        "\(formattedPageCount) • \(formattedSize)"
    }

    /// Size of the first page in points, for new blank pages.
    var firstPageSize: CGSize? {
        guard let renderer = try? MuPDFRenderer(url: url) else { return nil }
        let size = renderer.pageSize(at: 0)
        return size.width > 0 && size.height > 0 ? size : nil
    }

    /// Formatted import date
    var formattedImportDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: importDate, relativeTo: Date())
    }

    // MARK: - Initialization

    /// Creates document info from a URL and page count
    init(url: URL, pageCount: Int) {
        self.id = UUID()
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.pageCount = pageCount
        self.importDate = Date()

        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            self.fileSize = size
        } else {
            self.fileSize = 0
        }
    }

    /// Creates document info from a MuPDFDocument
    init(from muDocument: MuPDFDocument) {
        self.id = UUID()
        self.url = muDocument.sourceURL
        self.name = muDocument.fileName
        self.fileSize = muDocument.originalFileSize
        self.pageCount = muDocument.pageCount
        self.importDate = Date()
    }

    // MARK: - Equatable

    static func == (lhs: PDFDocumentInfo, rhs: PDFDocumentInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension PDFDocumentInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
