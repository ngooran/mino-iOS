//
//  MergeService.swift
//  Mino
//
//  Service for managing PDF merge operations
//

import Foundation

/// Service that manages PDF merge jobs
@Observable
@MainActor
final class MergeService {

    // MARK: - Properties

    /// The merge engine
    private let merger = PDFMerger()

    /// The current merge job
    private(set) var currentJob: MergeJob?

    /// Recent merge results (persisted)
    private(set) var recentResults: [MergeResult] = []

    /// Whether a merge is in progress
    private(set) var isMerging = false

    /// Maximum number of recent results to keep
    private let maxRecentResults = 50

    /// Storage key for persistence
    private let storageKey = "mergeResults"

    // MARK: - Initialization

    init() {
        loadResults()
    }

    // MARK: - Merge Operations

    /// Merges multiple documents into a single PDF
    func merge(
        documents: [PDFDocumentInfo],
        outputName: String
    ) async throws -> MergeResult {
        guard documents.count >= 2 else {
            throw MuPDFError.invalidParameters
        }

        // Create job
        let job = MergeJob(sourceDocuments: documents, outputName: outputName)
        currentJob = job
        isMerging = true

        // Start
        job.updateState(.preparing)

        // Generate output URL
        let outputURL = PDFMerger.generateOutputURL(outputName: outputName)

        do {
            // Capture values for detached task
            let merger = self.merger
            let sourceURLs = documents.map { $0.url }

            // Perform merge on background thread with progress updates
            let result = try await Task.detached(priority: .userInitiated) {
                try merger.merge(
                    sources: sourceURLs,
                    outputURL: outputURL,
                    progressHandler: { progress, currentFile in
                        Task { @MainActor in
                            job.updateState(.merging(progress: progress, currentFile: currentFile))
                        }
                    }
                )
            }.value

            // Update job state
            job.updateState(.completed)
            job.setResult(result)

            // Add to recent results and persist
            addToRecentResults(result)

            isMerging = false
            return result

        } catch {
            job.updateState(.failed(error: error.localizedDescription))
            isMerging = false
            throw error
        }
    }

    /// Clears the current job
    func clearCurrentJob() {
        currentJob = nil
    }

    // MARK: - Result Management

    /// Deletes a single merge result and its file
    func deleteResult(_ result: MergeResult) {
        // Remove file from disk
        try? FileManager.default.removeItem(at: result.outputURL)
        // Remove from list
        recentResults.removeAll { $0.id == result.id }
        // Persist changes
        persistResults()
    }

    /// Clears all recent results and their files
    func clearAllResults() {
        for result in recentResults {
            try? FileManager.default.removeItem(at: result.outputURL)
        }
        recentResults.removeAll()
        persistResults()
    }

    // MARK: - Private Methods

    private func addToRecentResults(_ result: MergeResult) {
        recentResults.insert(result, at: 0)
        if recentResults.count > maxRecentResults {
            let removed = Array(recentResults.suffix(from: maxRecentResults))
            for old in removed {
                try? FileManager.default.removeItem(at: old.outputURL)
            }
            recentResults = Array(recentResults.prefix(maxRecentResults))
        }
        persistResults()
    }

    // MARK: - Persistence

    /// Storage struct that uses relative paths (survives app container changes)
    private struct StoredResult: Codable {
        let id: UUID
        let relativePath: String
        let sourceCount: Int
        let totalPages: Int
        let outputSize: Int64
        let duration: TimeInterval
        let timestamp: Date
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func loadResults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            let stored = try JSONDecoder().decode([StoredResult].self, from: data)
            recentResults = stored.compactMap { item -> MergeResult? in
                let fullURL = documentsDirectory
                    .appendingPathComponent(item.relativePath)
                    .standardizedFileURL
                guard FileManager.default.fileExists(atPath: fullURL.path) else {
                    return nil
                }
                return MergeResult(
                    id: item.id,
                    outputURL: fullURL,
                    sourceCount: item.sourceCount,
                    totalPages: item.totalPages,
                    outputSize: item.outputSize,
                    duration: item.duration,
                    timestamp: item.timestamp
                )
            }
            if recentResults.count != stored.count {
                persistResults()
            }
        } catch {
            print("Failed to load merge results: \(error)")
        }
    }

    private func persistResults() {
        do {
            let docsPath = documentsDirectory.standardizedFileURL.path
            let stored = recentResults.map { result -> StoredResult in
                let fullPath = result.outputURL.standardizedFileURL.path
                let relativePath: String
                if fullPath.hasPrefix(docsPath + "/") {
                    relativePath = String(fullPath.dropFirst(docsPath.count + 1))
                } else if fullPath.hasPrefix(docsPath) {
                    relativePath = String(fullPath.dropFirst(docsPath.count))
                } else {
                    relativePath = result.outputURL.lastPathComponent
                }
                return StoredResult(
                    id: result.id,
                    relativePath: relativePath,
                    sourceCount: result.sourceCount,
                    totalPages: result.totalPages,
                    outputSize: result.outputSize,
                    duration: result.duration,
                    timestamp: result.timestamp
                )
            }
            let data = try JSONEncoder().encode(stored)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save merge results: \(error)")
        }
    }
}
