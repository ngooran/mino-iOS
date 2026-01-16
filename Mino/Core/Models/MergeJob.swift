//
//  MergeJob.swift
//  Mino
//
//  Model for tracking PDF merge job state
//

import Foundation
import SwiftUI

/// State of a merge job
enum MergeJobState: Sendable {
    case idle
    case preparing
    case merging(progress: Double, currentFile: String)
    case saving
    case completed
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .preparing, .merging, .saving:
            return true
        default:
            return false
        }
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

    var progress: Double {
        switch self {
        case .idle:
            return 0
        case .preparing:
            return 0.05
        case .merging(let progress, _):
            return 0.05 + progress * 0.85
        case .saving:
            return 0.95
        case .completed:
            return 1.0
        case .failed:
            return 0
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing..."
        case .merging(_, let currentFile):
            return "Merging \(currentFile)..."
        case .saving:
            return "Saving..."
        case .completed:
            return "Complete!"
        case .failed(let error):
            return error
        }
    }
}

/// Result of a successful merge operation
struct MergeResult: Identifiable, Sendable, Codable {
    let id: UUID
    let outputURL: URL
    let sourceCount: Int
    let totalPages: Int
    let outputSize: Int64
    let duration: TimeInterval
    let timestamp: Date

    /// Formatted output file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file)
    }

    /// Formatted duration
    var formattedDuration: String {
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

    /// Output filename
    var fileName: String {
        outputURL.deletingPathExtension().lastPathComponent
    }

    /// Summary text
    var summary: String {
        "\(sourceCount) files merged • \(totalPages) pages"
    }
}

/// Observable merge job for UI binding
@Observable
final class MergeJob: Identifiable {

    // MARK: - Properties

    let id: UUID
    var sourceDocuments: [PDFDocumentInfo]
    var outputName: String

    private(set) var state: MergeJobState = .idle
    private(set) var startTime: Date?
    private(set) var endTime: Date?
    private(set) var result: MergeResult?

    // MARK: - Computed Properties

    /// Total pages across all source documents
    var totalPages: Int {
        sourceDocuments.reduce(0) { $0 + $1.pageCount }
    }

    /// Total size of source documents
    var totalSourceSize: Int64 {
        sourceDocuments.reduce(0) { $0 + $1.fileSize }
    }

    /// Formatted total source size
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSourceSize, countStyle: .file)
    }

    /// Duration of the job (nil if not started)
    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    /// Whether the job can be started
    var canStart: Bool {
        sourceDocuments.count >= 2 && !state.isActive
    }

    /// The error message if failed
    var errorMessage: String? {
        if case .failed(let error) = state {
            return error
        }
        return nil
    }

    // MARK: - Initialization

    init(sourceDocuments: [PDFDocumentInfo] = [], outputName: String = "") {
        self.id = UUID()
        self.sourceDocuments = sourceDocuments
        self.outputName = outputName
    }

    // MARK: - Document Management

    /// Add a document to merge
    func addDocument(_ document: PDFDocumentInfo) {
        sourceDocuments.append(document)
    }

    /// Remove a document at index
    func removeDocument(at index: Int) {
        guard index >= 0 && index < sourceDocuments.count else { return }
        sourceDocuments.remove(at: index)
    }

    /// Move documents for reordering
    func moveDocuments(from source: IndexSet, to destination: Int) {
        sourceDocuments.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - State Updates

    /// Updates the job state
    func updateState(_ newState: MergeJobState) {
        switch newState {
        case .preparing, .merging, .saving:
            if startTime == nil {
                startTime = Date()
            }
        case .completed, .failed:
            if endTime == nil {
                endTime = Date()
            }
        default:
            break
        }
        state = newState
    }

    /// Sets the result
    func setResult(_ result: MergeResult) {
        self.result = result
    }

    /// Resets the job to idle state
    func reset() {
        state = .idle
        startTime = nil
        endTime = nil
        result = nil
    }
}

// MARK: - Equatable

extension MergeJob: Equatable {
    static func == (lhs: MergeJob, rhs: MergeJob) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension MergeJob: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
