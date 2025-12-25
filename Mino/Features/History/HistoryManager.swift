//
//  HistoryManager.swift
//  Mino
//
//  Manages compression history and statistics
//

import Foundation

@Observable
final class HistoryManager {
    static let shared = HistoryManager()

    // MARK: - Properties

    private(set) var history: [CompressionHistoryEntry] = []

    private let storageKey = "compressionHistory"
    private let maxEntries = 100

    // MARK: - Computed Statistics

    /// Total number of files compressed
    var totalFilesCompressed: Int {
        history.count
    }

    /// Total bytes processed (original sizes)
    var totalBytesProcessed: Int64 {
        history.reduce(0) { $0 + $1.originalSize }
    }

    /// Total bytes saved
    var totalBytesSaved: Int64 {
        history.reduce(0) { $0 + $1.savedBytes }
    }

    /// Average reduction percentage
    var averageReduction: Double {
        guard !history.isEmpty else { return 0 }
        return history.reduce(0) { $0 + $1.reductionPercentage } / Double(history.count)
    }

    /// Formatted total bytes saved
    var formattedTotalSaved: String {
        ByteCountFormatter.string(fromByteCount: totalBytesSaved, countStyle: .file)
    }

    /// Formatted total bytes processed
    var formattedTotalProcessed: String {
        ByteCountFormatter.string(fromByteCount: totalBytesProcessed, countStyle: .file)
    }

    /// Formatted average reduction
    var formattedAverageReduction: String {
        String(format: "%.1f%%", averageReduction)
    }

    // MARK: - Initialization

    private init() {
        loadHistory()
    }

    // MARK: - Public Methods

    /// Adds a new entry from a compression result
    func addEntry(from result: CompressionResult, originalFileName: String) {
        let entry = CompressionHistoryEntry(
            originalFileName: originalFileName,
            originalSize: result.originalSize,
            compressedSize: result.compressedSize,
            duration: result.duration,
            qualityUsed: result.settings.displayName
        )

        history.insert(entry, at: 0)

        // Trim to max entries
        if history.count > maxEntries {
            history = Array(history.prefix(maxEntries))
        }

        persistHistory()
    }

    /// Clears all history
    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    /// Deletes a specific entry
    func deleteEntry(_ entry: CompressionHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        persistHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            let entries = try JSONDecoder().decode([CompressionHistoryEntry].self, from: data)
            history = entries
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func persistHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}
