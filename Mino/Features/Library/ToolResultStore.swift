//
//  ToolResultStore.swift
//  Mino
//
//  Results of the tools added after 2.0, newest first, persisted through
//  StorageRoot.
//

import Foundation

@Observable
@MainActor
final class ToolResultStore {

    private(set) var results: [ToolResult] = []

    private let storageKey = "toolResults"
    private let maxResults = 200

    init() {
        load()
    }

    /// Adds the files an engine wrote to the library.
    @discardableResult
    func add(_ output: ToolOutput, tool: Tool) -> ToolResult {
        let result = ToolResult(tool: tool, output: output)
        results.insert(result, at: 0)
        if results.count > maxResults {
            for old in results.suffix(from: maxResults) { removeFiles(of: old) }
            results = Array(results.prefix(maxResults))
        }
        persist()
        return result
    }

    func result(id: UUID) -> ToolResult? {
        results.first { $0.id == id }
    }

    func delete(id: UUID) {
        guard let result = result(id: id) else { return }
        removeFiles(of: result)
        results.removeAll { $0.id == id }
        persist()
    }

    func clearAllResults() {
        results.forEach(removeFiles(of:))
        results.removeAll()
        persist()
    }

    private func removeFiles(of result: ToolResult) {
        result.urls.forEach(OutputLocation.removeFile(at:))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = StorageRoot.defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([StoredToolResult].self, from: data) else { return }
        results = stored.compactMap(\.result)
        if results.count != stored.count { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(results.map(StoredToolResult.init)) else { return }
        StorageRoot.defaults.set(data, forKey: storageKey)
    }
}
