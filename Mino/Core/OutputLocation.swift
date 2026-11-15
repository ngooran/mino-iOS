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
    nonisolated static func url(folder: String, fileName: String) -> URL {
        let directory = StorageRoot.documents
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent(sanitized(fileName))
            .appendingPathExtension("pdf")
    }

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

    /// Removes characters that are not allowed in file names and trims the length.
    nonisolated static func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Document" : String(cleaned.prefix(120))
    }
}
