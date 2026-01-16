//
//  BatchCompressionService.swift
//  Mino
//
//  Service for managing batch PDF compression operations
//

import Foundation

/// Service that manages batch PDF compression jobs
@Observable
@MainActor
final class BatchCompressionService {

    // MARK: - Properties

    /// The compression engine
    private let compressor = PDFCompressor()

    /// The current batch queue
    private(set) var currentQueue: BatchCompressionQueue?

    /// Whether batch compression is in progress
    private(set) var isProcessing = false

    /// Whether the batch was cancelled
    private var isCancelled = false

    // MARK: - Batch Operations

    /// Starts batch compression of multiple documents (sequential processing)
    func startBatch(
        documents: [PDFDocumentInfo],
        settings: CompressionSettings
    ) async throws -> [CompressionResult] {
        guard !documents.isEmpty else {
            throw MuPDFError.invalidParameters
        }

        // Create queue
        let queue = BatchCompressionQueue(documents: documents, settings: settings)
        currentQueue = queue
        isProcessing = true
        isCancelled = false

        // Start processing
        queue.updateState(.processing(currentIndex: 0, total: queue.count))

        var results: [CompressionResult] = []
        let compressor = self.compressor

        // Process documents sequentially
        for (index, item) in queue.items.enumerated() {
            // Check for cancellation
            if isCancelled {
                queue.updateState(.cancelled)
                break
            }

            // Update queue state
            queue.updateState(.processing(currentIndex: index, total: queue.count))

            // Update item state
            item.updateState(.compressing(progress: 0))

            // Generate output URL
            let outputURL = PDFCompressor.generateOutputURL(for: item.document.url, settings: settings)

            do {
                // Capture values for detached task
                let documentURL = item.document.url

                // Perform compression on background thread
                let result = try await Task.detached(priority: .userInitiated) {
                    try compressor.compress(
                        documentURL: documentURL,
                        settings: settings,
                        outputURL: outputURL
                    )
                }.value

                // Update item state
                item.updateState(.completed(result: result))
                results.append(result)

            } catch {
                // Mark item as failed but continue with next
                item.updateState(.failed(error: error.localizedDescription))
            }
        }

        // Update final state
        if !isCancelled {
            queue.updateState(.completed)
        }

        isProcessing = false
        return results
    }

    /// Starts batch compression with a quality preset
    func startBatch(
        documents: [PDFDocumentInfo],
        quality: CompressionQuality
    ) async throws -> [CompressionResult] {
        try await startBatch(documents: documents, settings: quality.settings)
    }

    /// Cancels the current batch
    func cancelBatch() {
        isCancelled = true
    }

    /// Pauses the current batch (marks state but doesn't stop current item)
    func pauseBatch() {
        guard let queue = currentQueue else { return }
        if case .processing(let index, let total) = queue.state {
            queue.updateState(.paused(currentIndex: index, total: total))
        }
    }

    /// Resumes a paused batch
    func resumeBatch() async throws -> [CompressionResult] {
        guard let queue = currentQueue else {
            throw MuPDFError.invalidParameters
        }

        // Get remaining items
        let completedCount = queue.completedCount
        let remainingDocuments = queue.items
            .dropFirst(completedCount)
            .filter { !$0.state.isCompleted && !$0.state.isFailed }
            .map { $0.document }

        guard !remainingDocuments.isEmpty else {
            return queue.results
        }

        // Continue processing
        isProcessing = true
        isCancelled = false

        var newResults: [CompressionResult] = []
        let settings = queue.settings
        let compressor = self.compressor

        for (offset, item) in queue.items.enumerated() where offset >= completedCount {
            // Skip already completed or failed
            guard !item.state.isCompleted && !item.state.isFailed else { continue }

            // Check for cancellation
            if isCancelled {
                queue.updateState(.cancelled)
                break
            }

            // Update states
            queue.updateState(.processing(currentIndex: offset, total: queue.count))
            item.updateState(.compressing(progress: 0))

            // Generate output URL
            let outputURL = PDFCompressor.generateOutputURL(for: item.document.url, settings: settings)

            do {
                let documentURL = item.document.url

                let result = try await Task.detached(priority: .userInitiated) {
                    try compressor.compress(
                        documentURL: documentURL,
                        settings: settings,
                        outputURL: outputURL
                    )
                }.value

                item.updateState(.completed(result: result))
                newResults.append(result)

            } catch {
                item.updateState(.failed(error: error.localizedDescription))
            }
        }

        if !isCancelled {
            queue.updateState(.completed)
        }

        isProcessing = false
        return queue.results
    }

    /// Clears the current queue
    func clearQueue() {
        currentQueue = nil
        isCancelled = false
    }

    /// Skips the current item in the queue
    func skipCurrentItem() {
        guard let queue = currentQueue,
              let currentIndex = queue.currentIndex,
              let item = queue.item(at: currentIndex) else { return }
        item.updateState(.skipped)
    }
}
