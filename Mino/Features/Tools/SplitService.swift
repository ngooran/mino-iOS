//
//  SplitService.swift
//  Mino
//
//  Service for managing PDF split operations
//

import Foundation

/// Service that manages PDF split jobs
@Observable
@MainActor
final class SplitService {

    // MARK: - Properties

    /// The split engine
    private let splitter = PDFSplitter()

    /// The current split job
    private(set) var currentJob: SplitJob?

    /// Recent split results (persisted)
    private(set) var recentResults: [SplitResult] = []

    /// Whether a split is in progress
    private(set) var isSplitting = false

    /// Maximum number of recent results to keep
    private let maxRecentResults = 100

    /// Storage key for persistence
    private let storageKey = "splitResults"

    // MARK: - Initialization

    init() {
        loadResults()
    }

    // MARK: - Split Operations

    /// Extracts a page range from a document
    func extractRange(
        from document: PDFDocumentInfo,
        range: PageRange
    ) async throws -> SplitResult {
        // Create job
        let job = SplitJob(sourceDocument: document, range: range)
        currentJob = job
        isSplitting = true

        // Start
        job.updateState(.preparing)

        // Generate output URL
        let outputURL = PDFSplitter.generateOutputURL(for: document.url, range: range)

        do {
            // Capture values for detached task
            let splitter = self.splitter
            let sourceURL = document.url

            // Update state
            job.updateState(.splitting(progress: 0.5, currentPage: range.start, totalPages: range.pageCount))

            // Perform extraction on background thread
            let result = try await Task.detached(priority: .userInitiated) {
                try splitter.extractRange(
                    sourceURL: sourceURL,
                    range: range,
                    outputURL: outputURL
                )
            }.value

            // Update job state
            job.updateState(.completed)
            job.addResult(result)

            // Add to recent results and persist
            addToRecentResults(result)

            isSplitting = false
            return result

        } catch {
            job.updateState(.failed(error: error.localizedDescription))
            isSplitting = false
            throw error
        }
    }

    /// Splits a document at a specific page into two files
    func splitAtPage(
        document: PDFDocumentInfo,
        splitPage: Int
    ) async throws -> [SplitResult] {
        // Create job
        let job = SplitJob(sourceDocument: document, splitMode: .splitAtPage(splitPage))
        currentJob = job
        isSplitting = true

        // Start
        job.updateState(.preparing)

        // Generate output URLs
        let outputURLs = PDFSplitter.generateSplitAtPageURLs(
            for: document.url,
            splitPage: splitPage,
            totalPages: document.pageCount
        )

        do {
            // Capture values for detached task
            let splitter = self.splitter
            let sourceURL = document.url

            // Update state
            job.updateState(.splitting(progress: 0.5, currentPage: splitPage, totalPages: document.pageCount))

            // Perform split on background thread
            let results = try await Task.detached(priority: .userInitiated) {
                try splitter.splitAtPage(
                    sourceURL: sourceURL,
                    splitPage: splitPage,
                    outputURL1: outputURLs.part1,
                    outputURL2: outputURLs.part2
                )
            }.value

            // Update job state
            job.updateState(.completed)
            for result in results {
                job.addResult(result)
            }

            // Add to recent results and persist
            for result in results {
                addToRecentResults(result)
            }

            isSplitting = false
            return results

        } catch {
            job.updateState(.failed(error: error.localizedDescription))
            isSplitting = false
            throw error
        }
    }

    /// Clears the current job
    func clearCurrentJob() {
        currentJob = nil
    }

    // MARK: - Result Management

    /// Deletes a single split result and its file
    func deleteResult(_ result: SplitResult) {
        try? FileManager.default.removeItem(at: result.outputURL)
        recentResults.removeAll { $0.id == result.id }
        persistResults()
    }

    /// Deletes multiple split results
    func deleteResults(_ results: [SplitResult]) {
        for result in results {
            try? FileManager.default.removeItem(at: result.outputURL)
        }
        let idsToRemove = Set(results.map { $0.id })
        recentResults.removeAll { idsToRemove.contains($0.id) }
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

    private func addToRecentResults(_ result: SplitResult) {
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
        let pageRange: String
        let pageCount: Int
        let outputSize: Int64
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
            recentResults = stored.compactMap { item -> SplitResult? in
                let fullURL = documentsDirectory
                    .appendingPathComponent(item.relativePath)
                    .standardizedFileURL
                guard FileManager.default.fileExists(atPath: fullURL.path) else {
                    return nil
                }
                return SplitResult(
                    id: item.id,
                    outputURL: fullURL,
                    pageRange: item.pageRange,
                    pageCount: item.pageCount,
                    outputSize: item.outputSize,
                    timestamp: item.timestamp
                )
            }
            if recentResults.count != stored.count {
                persistResults()
            }
        } catch {
            print("Failed to load split results: \(error)")
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
                    pageRange: result.pageRange,
                    pageCount: result.pageCount,
                    outputSize: result.outputSize,
                    timestamp: result.timestamp
                )
            }
            let data = try JSONEncoder().encode(stored)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save split results: \(error)")
        }
    }
}
