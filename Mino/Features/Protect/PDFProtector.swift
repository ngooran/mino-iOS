//
//  PDFProtector.swift
//  Mino
//
//  Protect & Unlock: add a password (AES-256), or save a copy without one.
//  Unlock removes a password the person knows. It never guesses one.
//

import Foundation

nonisolated enum PDFProtector {

    enum ProtectError: LocalizedError {
        case emptyPassword
        case passwordTooLong
        case unsupportedCharacters
        case notEncrypted
        case wrongPassword
        case needsPermissionsPassword

        var errorDescription: String? {
            switch self {
            case .emptyPassword:
                return String(localized: "Enter a password.")
            case .passwordTooLong:
                return String(localized: "The password is too long. Use up to 120 characters.")
            case .unsupportedCharacters:
                return String(localized: "Use only letters, numbers and symbols from the English keyboard. Other characters don't work in every PDF app.")
            case .notEncrypted:
                return String(localized: "This PDF has no password to remove.")
            case .wrongPassword:
                return String(localized: "That password didn't work.")
            case .needsPermissionsPassword:
                return String(localized: "That is not the permissions password of this PDF.")
            }
        }
    }

    /// PDF permission bits (ISO 32000, table 22).
    private enum Permission {
        static let print: Int32 = 1 << 2
        static let copy: Int32 = 1 << 4
        static let printHighQuality: Int32 = 1 << 11
    }

    /// Saves a copy that needs `password` to open.
    static func protect(
        documentURL: URL,
        password: String,
        allowPrinting: Bool,
        allowCopying: Bool,
        outputURL: URL
    ) throws {
        guard !password.isEmpty else { throw ProtectError.emptyPassword }
        guard password.utf8.count <= 120 else { throw ProtectError.passwordTooLong }
        guard isPortable(password) else { throw ProtectError.unsupportedCharacters }

        var permissions: Int32 = ~0
        if !allowPrinting { permissions &= ~(Permission.print | Permission.printHighQuality) }
        if !allowCopying { permissions &= ~Permission.copy }

        // With restrictions, the owner password must differ from the one that
        // opens the file, or opening it would lift them. Nobody needs to know
        // it: Unlock works with the opening password.
        let restricted = !allowPrinting || !allowCopying
        let ownerPassword = restricted ? randomPassword() : password

        try MuPDF.withPDF(at: documentURL) { ctx, _, pdf in
            MuPDF.prepareOutput(outputURL)
            guard mino_save_encrypted(ctx, pdf, outputURL.path, password, ownerPassword, permissions) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
        }
    }

    /// Saves a copy without encryption.
    /// - Parameter password: The password that opens the PDF, or its
    ///   permissions password when it opens freely. Nil for a working copy
    ///   that was already unlocked on import.
    static func unlock(documentURL: URL, password: String?, outputURL: URL) throws {
        try MuPDF.withPDF(at: documentURL) { ctx, doc, pdf in
            if mino_is_encrypted(ctx, pdf) != 0 {
                let needsPassword = mino_needs_password(ctx, doc) != 0
                let result = MuPDF.authenticate(ctx, doc, password: password ?? "")
                if needsPassword {
                    guard result != 0 else { throw ProtectError.wrongPassword }
                } else {
                    // Opens freely: only the owner may lift the restrictions.
                    guard password?.isEmpty == false, result & 4 != 0 else { throw ProtectError.needsPermissionsPassword }
                }
            } else if password != nil {
                throw ProtectError.notEncrypted
            }
            MuPDF.prepareOutput(outputURL)
            guard mino_save_decrypted(ctx, pdf, outputURL.path) == 0 else {
                throw MuPDFError.saveFailed(reason: MuPDF.lastError())
            }
        }
    }

    /// True when a password consists of printable ASCII only. PDF apps turn
    /// other characters into bytes in different ways: a file protected with
    /// "café" by MuPDF (UTF-8, as the PDF 2.0 standard says) does not open
    /// with "café" in Apple's PDFKit. ASCII works everywhere.
    static func isPortable(_ password: String) -> Bool {
        password.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
    }

    /// Whether a file is encrypted, and whether it needs a password to open.
    static func encryption(of url: URL) -> (isEncrypted: Bool, needsPassword: Bool) {
        (try? MuPDF.withPDF(at: url) { ctx, doc, pdf in
            (mino_is_encrypted(ctx, pdf) != 0, mino_needs_password(ctx, doc) != 0)
        }) ?? (false, false)
    }

    private static func randomPassword() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in characters.randomElement(using: &generator)! })
    }
}
