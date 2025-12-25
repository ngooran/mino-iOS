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

    /// Recent compression results
    private(set) var recentResults: [CompressionResult] = []

    /// Whether compression is in progress
    private(set) var isCompressing = false

    /// Maximum number of recent results to keep
    private let maxRecentResults = 20

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

            // Perform compression on background thread
            let result = try await Task.detached(priority: .userInitiated) {
                try self.compressor.compress(
                    documentURL: document.url,
                    settings: settings,
                    outputURL: outputURL
                )
            }.value

            // Update job state
            job.updateState(.completed(result: result))

            // Add to recent results
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

    /// Clears all recent results
    func clearRecentResults() {
        recentResults.removeAll()
    }

    /// Deletes a compression result and its file
    func deleteResult(_ result: CompressionResult) {
        try? FileManager.default.removeItem(at: result.outputURL)
        recentResults.removeAll { $0.id == result.id }
    }

    // MARK: - Private Methods

    private func addToRecentResults(_ result: CompressionResult) {
        recentResults.insert(result, at: 0)
        if recentResults.count > maxRecentResults {
            recentResults = Array(recentResults.prefix(maxRecentResults))
        }
    }
}
