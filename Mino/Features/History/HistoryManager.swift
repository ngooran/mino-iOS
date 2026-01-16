//
//  HistoryManager.swift
//  Mino
//
//  Manages compression history and statistics
//

import Foundation
import StoreKit
import UIKit

@Observable
final class HistoryManager {
    static let shared = HistoryManager()

    // MARK: - Properties

    private(set) var history: [CompressionHistoryEntry] = []

    private let storageKey = "compressionHistory"
    private let maxEntries = 100

    // MARK: - Review Request Properties

    private let goodOperationsKey = "goodOperationsCount"
    private let lastReviewRequestKey = "lastReviewRequestDate"
    private let minimumGoodOperations = 2
    private let monthsBetweenRequests = 4

    /// Minimum reduction percentage to count as a "good" compression
    private let minimumGoodReduction: Double = 15.0

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

    // MARK: - Review Request

    /// Current count of good operations
    private var goodOperationsCount: Int {
        get { UserDefaults.standard.integer(forKey: goodOperationsKey) }
        set { UserDefaults.standard.set(newValue, forKey: goodOperationsKey) }
    }

    /// Date of last review request
    private var lastReviewRequestDate: Date? {
        get { UserDefaults.standard.object(forKey: lastReviewRequestKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastReviewRequestKey) }
    }

    /// Records a good compression operation (>15% reduction)
    func recordGoodCompression(reductionPercentage: Double) {
        guard reductionPercentage >= minimumGoodReduction else { return }
        goodOperationsCount += 1
    }

    /// Records a successful merge operation
    func recordGoodMerge() {
        goodOperationsCount += 1
    }

    /// Records a successful split operation
    func recordGoodSplit() {
        goodOperationsCount += 1
    }

    /// Checks if conditions are met and requests a review if appropriate
    func requestReviewIfAppropriate() {
        guard shouldRequestReview() else { return }

        lastReviewRequestDate = Date()

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                    AppStore.requestReview(in: scene)
                }
            }
        }
    }

    /// Determines if we should request a review
    private func shouldRequestReview() -> Bool {
        // Need at least minimum good operations
        guard goodOperationsCount >= minimumGoodOperations else { return false }

        // Check if we've never requested before
        guard let lastRequest = lastReviewRequestDate else {
            return true
        }

        // Check if enough months have passed
        let calendar = Calendar.current
        if let monthsAgo = calendar.date(byAdding: .month, value: -monthsBetweenRequests, to: Date()) {
            return lastRequest < monthsAgo
        }

        return false
    }
}
