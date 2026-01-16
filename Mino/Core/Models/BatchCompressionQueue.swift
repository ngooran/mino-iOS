//
//  BatchCompressionQueue.swift
//  Mino
//
//  Model for tracking batch compression queue state
//

import Foundation
import SwiftUI

/// State of an individual item in the batch queue
enum BatchItemState: Sendable {
    case pending
    case compressing(progress: Double)
    case completed(result: CompressionResult)
    case failed(error: String)
    case skipped

    var isActive: Bool {
        if case .compressing = self {
            return true
        }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }

    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var statusMessage: String {
        switch self {
        case .pending:
            return "Waiting..."
        case .compressing(let progress):
            return "\(Int(progress * 100))%"
        case .completed:
            return "Done"
        case .failed(let error):
            return error
        case .skipped:
            return "Skipped"
        }
    }
}

/// An individual item in the batch compression queue
@Observable
final class BatchCompressionItem: Identifiable {
    let id: UUID
    let document: PDFDocumentInfo
    var state: BatchItemState = .pending
    var result: CompressionResult?

    init(document: PDFDocumentInfo) {
        self.id = UUID()
        self.document = document
    }

    /// Update the state
    func updateState(_ newState: BatchItemState) {
        state = newState
        if case .completed(let compressionResult) = newState {
            result = compressionResult
        }
    }
}

extension BatchCompressionItem: Equatable {
    static func == (lhs: BatchCompressionItem, rhs: BatchCompressionItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension BatchCompressionItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// State of the entire batch queue
enum BatchQueueState: Sendable {
    case idle
    case processing(currentIndex: Int, total: Int)
    case paused(currentIndex: Int, total: Int)
    case completed
    case cancelled

    var isActive: Bool {
        if case .processing = self {
            return true
        }
        return false
    }

    var isPaused: Bool {
        if case .paused = self {
            return true
        }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }

    var progress: Double {
        switch self {
        case .idle:
            return 0
        case .processing(let current, let total):
            return Double(current) / Double(total)
        case .paused(let current, let total):
            return Double(current) / Double(total)
        case .completed:
            return 1.0
        case .cancelled:
            return 0
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:
            return "Ready to start"
        case .processing(let current, let total):
            return "Processing \(current + 1) of \(total)..."
        case .paused(let current, let total):
            return "Paused at \(current + 1) of \(total)"
        case .completed:
            return "All files compressed!"
        case .cancelled:
            return "Cancelled"
        }
    }
}

/// Observable batch compression queue for UI binding
@Observable
final class BatchCompressionQueue: Identifiable {

    // MARK: - Properties

    let id: UUID
    var items: [BatchCompressionItem]
    let settings: CompressionSettings

    private(set) var state: BatchQueueState = .idle
    private(set) var startTime: Date?
    private(set) var endTime: Date?

    // MARK: - Computed Properties

    /// Number of items in the queue
    var count: Int {
        items.count
    }

    /// Number of completed items
    var completedCount: Int {
        items.filter { $0.state.isCompleted }.count
    }

    /// Number of failed items
    var failedCount: Int {
        items.filter { $0.state.isFailed }.count
    }

    /// Number of pending items
    var pendingCount: Int {
        items.filter {
            if case .pending = $0.state { return true }
            return false
        }.count
    }

    /// Current item being processed
    var currentItem: BatchCompressionItem? {
        items.first { $0.state.isActive }
    }

    /// Current item index
    var currentIndex: Int? {
        items.firstIndex { $0.state.isActive }
    }

    /// All successful results
    var results: [CompressionResult] {
        items.compactMap { $0.result }
    }

    /// Total original size of all documents
    var totalOriginalSize: Int64 {
        items.reduce(0) { $0 + $1.document.fileSize }
    }

    /// Total compressed size of completed items
    var totalCompressedSize: Int64 {
        results.reduce(0) { $0 + $1.compressedSize }
    }

    /// Total bytes saved
    var totalBytesSaved: Int64 {
        let completed = items.filter { $0.state.isCompleted }
        return completed.reduce(0) { total, item in
            guard let result = item.result else { return total }
            return total + (item.document.fileSize - result.compressedSize)
        }
    }

    /// Average compression ratio
    var averageReduction: Double {
        guard !results.isEmpty else { return 0 }
        let totalReduction = results.reduce(0.0) { $0 + (1.0 - $1.compressionRatio) }
        return totalReduction / Double(results.count)
    }

    /// Duration of the batch job
    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    /// Formatted duration
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1f sec", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    /// Formatted total bytes saved
    var formattedBytesSaved: String {
        ByteCountFormatter.string(fromByteCount: totalBytesSaved, countStyle: .file)
    }

    /// Formatted average reduction percentage
    var formattedAverageReduction: String {
        String(format: "%.0f%%", averageReduction * 100)
    }

    /// Whether the queue can be started
    var canStart: Bool {
        !items.isEmpty && !state.isActive
    }

    /// Whether the queue can be paused
    var canPause: Bool {
        state.isActive
    }

    /// Whether the queue can be resumed
    var canResume: Bool {
        state.isPaused
    }

    // MARK: - Initialization

    init(documents: [PDFDocumentInfo], settings: CompressionSettings) {
        self.id = UUID()
        self.items = documents.map { BatchCompressionItem(document: $0) }
        self.settings = settings
    }

    /// Convenience initializer with quality preset
    convenience init(documents: [PDFDocumentInfo], quality: CompressionQuality) {
        self.init(documents: documents, settings: quality.settings)
    }

    // MARK: - Item Management

    /// Add a document to the queue
    func addDocument(_ document: PDFDocumentInfo) {
        let item = BatchCompressionItem(document: document)
        items.append(item)
    }

    /// Remove an item at index
    func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        let item = items[index]
        // Don't remove active items
        guard !item.state.isActive else { return }
        items.remove(at: index)
    }

    /// Move items for reordering
    func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - State Updates

    /// Updates the queue state
    func updateState(_ newState: BatchQueueState) {
        switch newState {
        case .processing:
            if startTime == nil {
                startTime = Date()
            }
        case .completed, .cancelled:
            if endTime == nil {
                endTime = Date()
            }
        default:
            break
        }
        state = newState
    }

    /// Get item at index
    func item(at index: Int) -> BatchCompressionItem? {
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    /// Reset the queue to start fresh
    func reset() {
        state = .idle
        startTime = nil
        endTime = nil
        for item in items {
            item.updateState(.pending)
        }
    }
}

// MARK: - Equatable

extension BatchCompressionQueue: Equatable {
    static func == (lhs: BatchCompressionQueue, rhs: BatchCompressionQueue) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension BatchCompressionQueue: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
