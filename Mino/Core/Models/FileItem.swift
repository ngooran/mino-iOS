//
//  FileItem.swift
//  Mino
//
//  One generated file (compressed, merged or split) for the Files list.
//

import Foundation

struct FileItem: Identifiable, Hashable, Sendable {

    enum Kind: String, CaseIterable, Sendable {
        case compressed
        case merged
        case split

        var title: String {
            switch self {
            case .compressed: return "Compressed"
            case .merged: return "Merged"
            case .split: return "Split"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let url: URL
    let size: Int64
    let date: Date
    /// Compressed files: size before compression.
    let originalSize: Int64?
    let pageCount: Int?
    /// Merged files: number of PDFs combined.
    let sourceCount: Int?
    /// Split files: pages taken from the source, e.g. "1-3, 7".
    let pageRange: String?

    // MARK: - Display

    /// File name without extension. Older builds used names like
    /// "Compressed_Report_1A2B3C4D_1731234567"; those are tidied up for display.
    var name: String {
        var name = url.deletingPathExtension().lastPathComponent
        for prefix in ["Compressed_", "Merged_"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        name = name.replacingOccurrences(of: #"_\d{9,}$"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"_[0-9A-F]{8}$"#, with: "", options: .regularExpression)
        return name
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Whole-number percentage saved by compression.
    var reductionPercent: Int? {
        guard let originalSize, originalSize > 0 else { return nil }
        return Int((Double(max(0, originalSize - size)) / Double(originalSize) * 100).rounded())
    }

    /// One-line summary of the outcome, shown under the name.
    var summary: String {
        switch kind {
        case .compressed:
            if let reductionPercent {
                return "\(formattedSize) · \(reductionPercent)% smaller"
            }
            return formattedSize
        case .merged:
            var parts: [String] = []
            if let pageCount { parts.append("\(pageCount) pages") }
            if let sourceCount { parts.append("\(sourceCount) PDFs merged") }
            parts.append(formattedSize)
            return parts.joined(separator: " · ")
        case .split:
            let pages = pageCount == 1 ? "Page" : "Pages"
            if let pageRange {
                return "\(pages) \(pageRange) · \(formattedSize)"
            }
            return formattedSize
        }
    }

    // MARK: - Init

    init(_ result: CompressionResult) {
        id = result.id
        kind = .compressed
        url = result.outputURL
        size = result.compressedSize
        date = result.timestamp
        originalSize = result.originalSize
        pageCount = nil
        sourceCount = nil
        pageRange = nil
    }

    init(_ result: MergeResult) {
        id = result.id
        kind = .merged
        url = result.outputURL
        size = result.outputSize
        date = result.timestamp
        originalSize = nil
        pageCount = result.totalPages
        sourceCount = result.sourceCount
        pageRange = nil
    }

    init(_ result: SplitResult) {
        id = result.id
        kind = .split
        url = result.outputURL
        size = result.outputSize
        date = result.timestamp
        originalSize = nil
        pageCount = result.pageCount
        sourceCount = nil
        pageRange = result.pageRange
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
    }
}
