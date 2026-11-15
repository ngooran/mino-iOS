//
//  Sessions.swift
//  Mino
//
//  State for each task (compress, merge, split). Sessions live in AppState,
//  so a task keeps its state when the layout changes (rotation, folding
//  iPhone Duo, resizing an iPad window).
//

import Foundation

/// Where a task is in its life cycle.
enum TaskPhase: Equatable {
    case configure
    case working
    case done
    case failed(String)
}

extension CompressionQuality {
    /// Outcome-oriented name shown in the quality picker.
    var title: String {
        switch self {
        case .low: return "Smallest"
        case .medium: return "Balanced"
        case .high: return "Best Quality"
        }
    }

    /// What the preset is good for.
    var useCase: String {
        switch self {
        case .low: return "for messages and uploads"
        case .medium: return "good for email"
        case .high: return "for printing"
        }
    }
}

// MARK: - Compress

@Observable
@MainActor
final class CompressSession: Identifiable {

    enum Choice: Hashable {
        case preset(CompressionQuality)
        case custom
    }

    let id = UUID()
    var documents: [PDFDocumentInfo]
    var choice: Choice
    /// Custom JPEG quality, 20–95.
    var imageQuality: Double = 60
    /// Custom target resolution in dpi, 72–300.
    var resolution: Double = 150

    var phase: TaskPhase = .configure
    var results: [CompressionResult] = []

    /// Estimated output size per preset (single file only).
    var estimates: [CompressionQuality: Int64] = [:]
    var isEstimating = false
    var estimateTask: Task<Void, Never>?

    /// Set when the person cancels; the finished output is then discarded.
    var wasCancelled = false

    init(documents: [PDFDocumentInfo], quality: CompressionQuality) {
        self.documents = documents
        self.choice = .preset(quality)
    }

    var isBatch: Bool { documents.count > 1 }

    var totalSize: Int64 { documents.reduce(0) { $0 + $1.fileSize } }

    var totalPages: Int { documents.reduce(0) { $0 + $1.pageCount } }

    var settings: CompressionSettings {
        switch choice {
        case .preset(let quality):
            return quality.settings
        case .custom:
            return CompressionSettings(jpegQuality: Int(imageQuality), targetDPI: Int(resolution))
        }
    }

    var originalTotal: Int64 { results.reduce(0) { $0 + $1.originalSize } }
    var compressedTotal: Int64 { results.reduce(0) { $0 + $1.compressedSize } }

    /// Whole-number percentage saved across all results.
    var reductionPercent: Int {
        guard originalTotal > 0 else { return 0 }
        return Int((Double(max(0, originalTotal - compressedTotal)) / Double(originalTotal) * 100).rounded())
    }
}

// MARK: - Merge

@Observable
@MainActor
final class MergeSession {
    var documents: [PDFDocumentInfo] = []
    var phase: TaskPhase = .configure
    var result: MergeResult?

    var totalPages: Int { documents.reduce(0) { $0 + $1.pageCount } }
    var totalSize: Int64 { documents.reduce(0) { $0 + $1.fileSize } }
}

// MARK: - Split

@Observable
@MainActor
final class SplitSession {

    enum Mode: Hashable {
        case choosePages
        case everyPage
    }

    let document: PDFDocumentInfo
    var mode: Mode = .choosePages
    var selectedPages: Set<Int> = []
    var phase: TaskPhase = .configure
    var results: [SplitResult] = []
    /// Pages finished during an every-page split.
    var completedPages = 0
    var task: Task<Void, Never>?

    init(document: PDFDocumentInfo) {
        self.document = document
    }

    /// Selected pages as text, e.g. "1-3, 7".
    var selectionText: String {
        PageRange.ranges(covering: Array(selectedPages)).map(\.displayString).joined(separator: ", ")
    }
}

// MARK: - Size estimate

/// Estimates compressed sizes by compressing a short sample of the document
/// with each preset and scaling the ratio to the whole file.
enum SizeEstimator {

    nonisolated static func estimate(
        documentURL: URL,
        fileSize: Int64,
        sampleRange: PageRange?,
        presets: [(key: String, settings: CompressionSettings)],
        compressor: PDFCompressor,
        splitter: PDFSplitter
    ) -> [String: Int64] {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory
            .appendingPathComponent("estimate-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }

        var sampleURL = documentURL
        var sampleSize = fileSize
        if let sampleRange {
            let url = temp.appendingPathComponent("sample.pdf")
            guard let sample = try? splitter.extractRange(sourceURL: documentURL, range: sampleRange, outputURL: url),
                  sample.outputSize > 0 else { return [:] }
            sampleURL = url
            sampleSize = sample.outputSize
        }

        var estimates: [String: Int64] = [:]
        for preset in presets {
            if Task.isCancelled { break }
            let outputURL = temp.appendingPathComponent("\(preset.key).pdf")
            guard let result = try? compressor.compress(documentURL: sampleURL, settings: preset.settings, outputURL: outputURL) else {
                continue
            }
            let ratio = min(1.0, Double(result.compressedSize) / Double(max(1, sampleSize)))
            estimates[preset.key] = Int64(Double(fileSize) * ratio)
        }
        return estimates
    }
}
