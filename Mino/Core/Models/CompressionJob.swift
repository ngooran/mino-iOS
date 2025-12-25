//
//  CompressionJob.swift
//  Mino
//
//  Model for tracking compression job state
//

import Foundation
import SwiftUI

/// State of a compression job
enum CompressionJobState: Sendable {
    case idle
    case preparing
    case compressing(progress: Double, phase: String)
    case completed(result: CompressionResult)
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .preparing, .compressing:
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
        case .compressing(let progress, _):
            return progress
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
        case .compressing(_, let phase):
            return phase
        case .completed:
            return "Complete!"
        case .failed(let error):
            return error
        }
    }
}

/// Observable compression job for UI binding
@Observable
final class CompressionJob: Identifiable {

    // MARK: - Properties

    let id: UUID
    let document: PDFDocumentInfo
    let settings: CompressionSettings

    /// Convenience accessor for preset quality
    var quality: CompressionQuality {
        settings.preset ?? .medium
    }

    private(set) var state: CompressionJobState = .idle
    private(set) var startTime: Date?
    private(set) var endTime: Date?

    // MARK: - Computed Properties

    /// Duration of the job (nil if not started)
    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    /// Formatted duration string
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

    /// Whether the job can be started
    var canStart: Bool {
        if case .idle = state { return true }
        return state.isFailed
    }

    /// Whether the job can be cancelled
    var canCancel: Bool {
        state.isActive
    }

    /// The result if completed
    var result: CompressionResult? {
        if case .completed(let result) = state {
            return result
        }
        return nil
    }

    /// The error message if failed
    var errorMessage: String? {
        if case .failed(let error) = state {
            return error
        }
        return nil
    }

    // MARK: - Initialization

    init(document: PDFDocumentInfo, settings: CompressionSettings) {
        self.id = UUID()
        self.document = document
        self.settings = settings
    }

    /// Convenience initializer with quality preset
    convenience init(document: PDFDocumentInfo, quality: CompressionQuality) {
        self.init(document: document, settings: quality.settings)
    }

    // MARK: - State Updates

    /// Updates the job state
    func updateState(_ newState: CompressionJobState) {
        switch newState {
        case .preparing, .compressing:
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

    /// Resets the job to idle state
    func reset() {
        state = .idle
        startTime = nil
        endTime = nil
    }
}

// MARK: - Equatable

extension CompressionJob: Equatable {
    static func == (lhs: CompressionJob, rhs: CompressionJob) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension CompressionJob: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
