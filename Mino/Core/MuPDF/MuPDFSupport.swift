//
//  MuPDFSupport.swift
//  Mino
//
//  Small helpers shared by the MuPDF engines.
//

import Foundation

nonisolated enum MuPDF {

    /// The message of the last failed wrapper call on this thread.
    static func lastError() -> String {
        guard let message = mino_get_last_error() else { return "Unknown error" }
        let text = String(cString: message)
        mino_clear_error()
        return text
    }

    /// Runs `body` with a fresh context that is dropped afterwards.
    static func withContext<T>(_ body: (UnsafeMutablePointer<fz_context>) throws -> T) throws -> T {
        guard let ctx = mino_create_context() else { throw MuPDFError.contextCreationFailed }
        defer { mino_drop_context(ctx) }
        return try body(ctx)
    }

    /// Opens a PDF, runs `body`, and closes it again.
    static func withPDF<T>(
        at url: URL,
        _ body: (UnsafeMutablePointer<fz_context>, UnsafeMutablePointer<fz_document>, UnsafeMutablePointer<pdf_document>) throws -> T
    ) throws -> T {
        try withContext { ctx in
            guard let doc = mino_open_document(ctx, url.path) else {
                throw MuPDFError.documentOpenFailed(path: url.path, reason: lastError())
            }
            defer { mino_drop_document(ctx, doc) }
            guard let pdf = mino_pdf_specifics(ctx, doc) else { throw MuPDFError.invalidPDFDocument }
            return try body(ctx, doc, pdf)
        }
    }

    /// Tries a password on an open document. Returns MuPDF's result bits
    /// (2 = user password, 4 = owner password), or 0 when it is wrong.
    ///
    /// PDF apps disagree on how characters outside ASCII are turned into
    /// bytes, so a password like "café" is tried as UTF-8 and as Latin-1.
    static func authenticate(
        _ ctx: UnsafeMutablePointer<fz_context>,
        _ doc: UnsafeMutablePointer<fz_document>,
        password: String
    ) -> Int32 {
        let result = mino_authenticate(ctx, doc, password)
        if result != 0 || password.utf8.allSatisfy({ $0 < 0x80 }) { return result }
        guard let latin1 = password.data(using: .isoLatin1) else { return 0 }
        let bytes = [UInt8](latin1) + [0]
        return bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) {
                mino_authenticate(ctx, doc, $0)
            }
        }
    }

    /// Removes a file that may be left over at an output location.
    static func prepareOutput(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
    }
}
