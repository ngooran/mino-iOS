//
//  PageOrganizer.swift
//  Mino
//
//  Organize Pages: rotate, delete, reorder, duplicate and insert. The open
//  document is changed in place and saved as a copy, so bookmarks, links and
//  form fields on the pages that stay are kept.
//

import Foundation

nonisolated enum PageOrganizer {

    /// Writes `documentURL` with its pages arranged as `pages` to `outputURL`.
    /// Returns the page count of the result.
    @discardableResult
    static func save(documentURL: URL, pages: [OrganizedPage], outputURL: URL) throws -> Int {
        guard !pages.isEmpty else { throw MuPDFError.invalidParameters }

        return try MuPDF.withPDF(at: documentURL) { ctx, doc, pdf in
            let originalCount = Int(mino_count_pages(ctx, doc))
            var nextExtra = originalCount
            // Index of each wanted page in the extended document (original
            // pages, then the copies, blanks and inserted pages appended below).
            var order: [Int32] = []
            var usedOriginals: Set<Int> = []
            var grafts: [URL: ExternalDocument] = [:]
            defer { grafts.values.forEach { $0.close(ctx) } }

            for page in pages {
                try Task.checkCancellation()
                switch page.source {
                case .original(let index):
                    guard index >= 0, index < originalCount else {
                        throw MuPDFError.invalidPageRange(start: index + 1, end: index + 1, pageCount: originalCount)
                    }
                    if usedOriginals.insert(index).inserted {
                        order.append(Int32(index))
                    } else {
                        // The same page again: a copy that shares its content.
                        guard mino_duplicate_page(ctx, pdf, Int32(index)) == 0 else {
                            throw MuPDFError.unknownError(MuPDF.lastError())
                        }
                        order.append(Int32(nextExtra))
                        nextExtra += 1
                    }
                case .blank(let width, let height):
                    guard mino_add_blank_page(ctx, pdf, Float(width), Float(height)) == 0 else {
                        throw MuPDFError.unknownError(MuPDF.lastError())
                    }
                    order.append(Int32(nextExtra))
                    nextExtra += 1
                case .external(let url, let index):
                    if grafts[url] == nil {
                        grafts[url] = try ExternalDocument(ctx: ctx, url: url, destination: pdf)
                    }
                    guard let external = grafts[url],
                          mino_graft_page(ctx, external.map, -1, external.pdf, Int32(index)) == 0 else {
                        throw MuPDFError.pageGraftFailed(page: index, reason: MuPDF.lastError())
                    }
                    order.append(Int32(nextExtra))
                    nextExtra += 1
                }
            }

            guard mino_rearrange_pages(ctx, pdf, Int32(order.count), order) == 0 else {
                throw MuPDFError.unknownError(MuPDF.lastError())
            }

            for (index, page) in pages.enumerated() where page.rotation % 360 != 0 {
                let current = Int(mino_get_page_rotation(ctx, pdf, Int32(index)))
                guard mino_set_page_rotation(ctx, pdf, Int32(index), Int32((current + page.rotation) % 360)) == 0 else {
                    throw MuPDFError.unknownError(MuPDF.lastError())
                }
            }

            MuPDF.prepareOutput(outputURL)
            // Garbage collection drops what belonged only to removed pages.
            guard mino_save_pdf(ctx, pdf, outputURL.path, 2) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
            return pages.count
        }
    }

    /// Another PDF whose pages are being inserted.
    private struct ExternalDocument {
        let doc: UnsafeMutablePointer<fz_document>
        let pdf: UnsafeMutablePointer<pdf_document>
        let map: OpaquePointer

        init(ctx: UnsafeMutablePointer<fz_context>, url: URL, destination: UnsafeMutablePointer<pdf_document>) throws {
            guard let doc = mino_open_document(ctx, url.path) else {
                throw MuPDFError.documentOpenFailed(path: url.path, reason: MuPDF.lastError())
            }
            guard let pdf = mino_pdf_specifics(ctx, doc), let map = mino_new_graft_map(ctx, destination) else {
                mino_drop_document(ctx, doc)
                throw MuPDFError.graftMapFailed
            }
            self.doc = doc
            self.pdf = pdf
            self.map = map
        }

        func close(_ ctx: UnsafeMutablePointer<fz_context>) {
            mino_drop_graft_map(ctx, map)
            mino_drop_document(ctx, doc)
        }
    }
}
