//
//  CompressionService.swift
//  Mino
//
//  Service for managing PDF compression operations
//

import Foundation

/// Service that manages PDF compression jobs
@Observable
@MainActor
final class CompressionService {

    // MARK: - Properties

    /// The compression engine
    private let compressor = PDFCompressor()

    /// The current compression job
    private(set) var currentJob: CompressionJob?

    /// Recent compression results (persisted)
    private(set) var recentResults: [CompressionResult] = []

    /// Whether compression is in progress
    private(set) var isCompressing = false

    /// Maximum number of recent results to keep
    private let maxRecentResults = 50

    /// Storage key for persistence
    private let storageKey = "compressionResults"

    // MARK: - Initialization

    init() {
        loadResults()
    }

    // MARK: - Compression

    /// Compresses a document with specified settings
    func compress(
        document: PDFDocumentInfo,
        settings: CompressionSettings
    ) async throws -> CompressionResult {
        // Create job
        let job = CompressionJob(document: document, settings: settings)
        currentJob = job
        isCompressing = true

        // Start
        job.updateState(.preparing)

        // Generate output URL
        let outputURL = PDFCompressor.generateOutputURL(for: document.url, settings: settings)

        do {
            // Update state
            job.updateState(.compressing(progress: 0.5, phase: "Compressing..."))

            // Capture values for detached task
            let compressor = self.compressor
            let documentURL = document.url

            // Perform compression on background thread
            let result = try await Task.detached(priority: .userInitiated) {
                try compressor.compress(
                    documentURL: documentURL,
                    settings: settings,
                    outputURL: outputURL
                )
            }.value

            // Update job state
            job.updateState(.completed(result: result))

            // Add to recent results and persist
            addToRecentResults(result)

            isCompressing = false
            return result

        } catch {
            job.updateState(.failed(error: error.localizedDescription))
            isCompressing = false
            throw error
        }
    }

    /// Compresses a document with specified quality preset
    func compress(
        document: PDFDocumentInfo,
        quality: CompressionQuality
    ) async throws -> CompressionResult {
        try await compress(document: document, settings: quality.settings)
    }

    /// Clears the current job
    func clearCurrentJob() {
        currentJob = nil
    }

    // MARK: - Result Management

    /// Deletes a single compression result and its file
    func deleteResult(_ result: CompressionResult) {
        // Remove file from disk
        try? FileManager.default.removeItem(at: result.outputURL)
        // Remove from list
        recentResults.removeAll { $0.id == result.id }
        // Persist changes
        persistResults()
    }

    /// Deletes multiple compression results
    func deleteResults(_ results: [CompressionResult]) {
        for result in results {
            try? FileManager.default.removeItem(at: result.outputURL)
        }
        let idsToRemove = Set(results.map { $0.id })
        recentResults.removeAll { idsToRemove.contains($0.id) }
        persistResults()
    }

    /// Clears all recent results and their files
    func clearAllResults() {
        // Remove all files
        for result in recentResults {
            try? FileManager.default.removeItem(at: result.outputURL)
        }
        // Clear list
        recentResults.removeAll()
        // Persist changes
        persistResults()
    }

    // MARK: - Private Methods

    private func addToRecentResults(_ result: CompressionResult) {
        recentResults.insert(result, at: 0)
        if recentResults.count > maxRecentResults {
            // Remove old results beyond limit (and their files)
            let removed = Array(recentResults.suffix(from: maxRecentResults))
            for old in removed {
                try? FileManager.default.removeItem(at: old.outputURL)
            }
            recentResults = Array(recentResults.prefix(maxRecentResults))
        }
        persistResults()
    }

    // MARK: - Persistence

    private func loadResults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            let results = try JSONDecoder().decode([CompressionResult].self, from: data)
            // Filter to only include results where the file still exists
            recentResults = results.filter { result in
                FileManager.default.fileExists(atPath: result.outputURL.path)
            }
            // If some files were missing, update persistence
            if recentResults.count != results.count {
                persistResults()
            }
        } catch {
            print("Failed to load compression results: \(error)")
        }
    }

    private func persistResults() {
        do {
            let data = try JSONEncoder().encode(recentResults)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save compression results: \(error)")
        }
    }
}
