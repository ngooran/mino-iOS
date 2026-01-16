//
//  SplitJob.swift
//  Mino
//
//  Model for tracking PDF split job state
//

import Foundation

/// Represents a page range for splitting
struct PageRange: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var start: Int  // 1-based for user display
    var end: Int    // 1-based for user display

    /// Number of pages in this range
    nonisolated var pageCount: Int {
        max(0, end - start + 1)
    }

    /// Display string (e.g., "1-5" or "3")
    nonisolated var displayString: String {
        if start == end {
            return "\(start)"
        }
        return "\(start)-\(end)"
    }

    init(start: Int, end: Int) {
        self.id = UUID()
        self.start = start
        self.end = end
    }

    /// Creates a single-page range
    init(page: Int) {
        self.id = UUID()
        self.start = page
        self.end = page
    }
}

/// How to split the PDF
enum SplitMode: Sendable {
    /// Extract a specific page range as a single PDF
    case pageRange(PageRange)

    /// Split PDF at a specific page into two parts
    /// The page number is where the second part begins (1-based)
    case splitAtPage(Int)

    /// Multiple custom ranges
    case customRanges([PageRange])

    var description: String {
        switch self {
        case .pageRange(let range):
            return "Extract pages \(range.displayString)"
        case .splitAtPage(let page):
            return "Split at page \(page)"
        case .customRanges(let ranges):
            return "Extract \(ranges.count) ranges"
        }
    }
}

/// State of a split job
enum SplitJobState: Sendable {
    case idle
    case preparing
    case splitting(progress: Double, currentPage: Int, totalPages: Int)
    case saving
    case completed
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .preparing, .splitting, .saving:
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
        case .splitting(let progress, _, _):
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
        case .splitting(_, let current, let total):
            return "Processing page \(current) of \(total)..."
        case .saving:
            return "Saving..."
        case .completed:
            return "Complete!"
        case .failed(let error):
            return error
        }
    }
}

/// Result of a single split output file
struct SplitResult: Identifiable, Sendable, Codable {
    let id: UUID
    let outputURL: URL
    let pageRange: String  // e.g., "1-5" or "3"
    let pageCount: Int
    let outputSize: Int64
    let timestamp: Date

    /// Formatted output file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file)
    }

    /// Output filename
    var fileName: String {
        outputURL.deletingPathExtension().lastPathComponent
    }

    /// Summary text
    var summary: String {
        if pageCount == 1 {
            return "Page \(pageRange) • \(formattedSize)"
        }
        return "Pages \(pageRange) • \(formattedSize)"
    }
}

/// Observable split job for UI binding
@Observable
final class SplitJob: Identifiable {

    // MARK: - Properties

    let id: UUID
    let sourceDocument: PDFDocumentInfo
    var splitMode: SplitMode

    private(set) var state: SplitJobState = .idle
    private(set) var startTime: Date?
    private(set) var endTime: Date?
    private(set) var results: [SplitResult] = []

    // MARK: - Computed Properties

    /// Number of output files that will be created
    var expectedOutputCount: Int {
        switch splitMode {
        case .pageRange:
            return 1
        case .splitAtPage:
            return 2
        case .customRanges(let ranges):
            return ranges.count
        }
    }

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

    /// Total size of all output files
    var totalOutputSize: Int64 {
        results.reduce(0) { $0 + $1.outputSize }
    }

    /// Formatted total output size
    var formattedTotalOutputSize: String {
        ByteCountFormatter.string(fromByteCount: totalOutputSize, countStyle: .file)
    }

    /// Whether the job can be started
    var canStart: Bool {
        !state.isActive
    }

    /// The error message if failed
    var errorMessage: String? {
        if case .failed(let error) = state {
            return error
        }
        return nil
    }

    // MARK: - Initialization

    init(sourceDocument: PDFDocumentInfo, splitMode: SplitMode) {
        self.id = UUID()
        self.sourceDocument = sourceDocument
        self.splitMode = splitMode
    }

    /// Convenience initializer for page range extraction
    convenience init(sourceDocument: PDFDocumentInfo, range: PageRange) {
        self.init(sourceDocument: sourceDocument, splitMode: .pageRange(range))
    }

    // MARK: - State Updates

    /// Updates the job state
    func updateState(_ newState: SplitJobState) {
        switch newState {
        case .preparing, .splitting, .saving:
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

    /// Adds a result
    func addResult(_ result: SplitResult) {
        results.append(result)
    }

    /// Resets the job to idle state
    func reset() {
        state = .idle
        startTime = nil
        endTime = nil
        results = []
    }
}

// MARK: - Equatable

extension SplitJob: Equatable {
    static func == (lhs: SplitJob, rhs: SplitJob) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension SplitJob: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
