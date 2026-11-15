//
//  OutputLocation.swift
//  Mino
//
//  Builds output file locations in the app's Documents folder.
//

import Foundation

/// Every operation writes into its own folder (`<Kind>/<UUID>/`), so the file
/// itself can keep a clean, shareable name such as "Lease Agreement.pdf".
enum OutputLocation {

    /// Returns a fresh URL like `Documents/Compressed/<UUID>/Lease Agreement.pdf`.
    nonisolated static func url(folder: String, fileName: String, fileExtension: String = "pdf") -> URL {
        directory(folder: folder)
            .appendingPathComponent(sanitized(fileName))
            .appendingPathExtension(fileExtension)
    }

    /// Returns a fresh, empty folder like `Documents/Images/<UUID>/` for an
    /// operation that writes several files.
    nonisolated static func directory(folder: String) -> URL {
        let directory = StorageRoot.documents
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Path of a stored file relative to the Documents folder, so it survives
    /// the app container moving.
    nonisolated static func relativePath(of url: URL) -> String {
        let base = StorageRoot.documents.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(base + "/") { return String(full.dropFirst(base.count + 1)) }
        return url.lastPathComponent
    }

    nonisolated static func resolve(relativePath: String) -> URL {
        StorageRoot.documents.appendingPathComponent(relativePath).standardizedFileURL
    }

    /// A scratch folder for inputs of the current session. Cleared at launch.
    nonisolated static func workingDirectory() -> URL {
        let directory = StorageRoot.documents
            .appendingPathComponent(workingFolder, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static let workingFolder = "ImportedPDFs"

    /// Deletes a generated file and its per-operation folder once that folder is empty.
    nonisolated static func removeFile(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        guard UUID(uuidString: parent.lastPathComponent) != nil,
              let contents = try? fileManager.contentsOfDirectory(atPath: parent.path),
              contents.isEmpty else { return }
        try? fileManager.removeItem(at: parent)
    }

    /// A date for default file names, e.g. "15 Nov".
    nonisolated static func shortDate(_ date: Date = Date()) -> String {
        // Some locales write "15. Nov."; file names read better without the periods.
        date.formatted(.dateTime.day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
    }

    /// Removes characters that are not allowed in file names and trims the length.
    nonisolated static func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Document" : String(cleaned.prefix(120))
    }
}
