//
//  FileItem.swift
//  Mino
//
//  One generated result for the Files list. Usually one file; PDF to Images
//  makes one item out of several image files.
//

import Foundation

nonisolated struct FileItem: Identifiable, Hashable, Sendable {

    enum Kind: String, CaseIterable, Sendable {
        case compressed
        case merged
        case split
        case scanned
        case converted
        case edited
        case signed
        case protected

        /// Name of the kind in the Files filter.
        var title: String {
            switch self {
            case .compressed: return String(localized: "Compressed")
            case .merged: return String(localized: "Merged")
            case .split: return String(localized: "Split")
            case .scanned: return String(localized: "Scans")
            case .converted: return String(localized: "Converted")
            case .edited: return String(localized: "Edited")
            case .signed: return String(localized: "Signed")
            case .protected: return String(localized: "Protected")
            }
        }

        var systemImage: String {
            switch self {
            case .compressed: return "arrow.down.doc"
            case .merged: return "doc.on.doc"
            case .split: return "scissors"
            case .scanned: return "doc.viewfinder"
            case .converted: return "arrow.left.arrow.right"
            case .edited: return "pencil"
            case .signed: return "signature"
            case .protected: return "lock"
            }
        }
    }

    let id: UUID
    let kind: Kind
    /// The file, or the first of several.
    let url: URL
    /// Every file of the result.
    let urls: [URL]
    let size: Int64
    let date: Date
    /// Compressed files: size before compression.
    let originalSize: Int64?
    let pageCount: Int?
    /// Merged files: number of PDFs combined.
    let sourceCount: Int?
    /// Split files: pages taken from the source, e.g. "1-3, 7".
    let pageRange: String?
    /// Results of the newer tools: the tool, and a short outcome.
    let tool: Tool?
    let detail: String?

    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }

    // MARK: - Display

    /// File name without extension. Older builds used names like
    /// "Compressed_Report_1A2B3C4D_1731234567"; those are tidied up for display.
    var name: String {
        if urls.count > 1 {
            // Several images: the folder-level name, without " - Page 1".
            let first = url.deletingPathExtension().lastPathComponent
            if let range = first.range(of: " - ", options: .backwards) {
                return String(first[..<range.lowerBound])
            }
            return first
        }
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
                return String(localized: "\(formattedSize) · \(reductionPercent)% smaller")
            }
            return formattedSize
        case .merged:
            var parts: [String] = []
            if let pageCount { parts.append(String(localized: "\(pageCount) pages")) }
            if let sourceCount { parts.append(String(localized: "\(sourceCount) PDFs merged")) }
            parts.append(formattedSize)
            return parts.joined(separator: " · ")
        case .split:
            if let pageRange {
                return pageCount == 1
                    ? String(localized: "Page \(pageRange) · \(formattedSize)")
                    : String(localized: "Pages \(pageRange) · \(formattedSize)")
            }
            return formattedSize
        case .scanned, .converted, .edited, .signed, .protected:
            var parts = [formattedSize]
            if let detail {
                parts.append(detail)
            } else if let pageCount, isPDF {
                parts.append(String(localized: "\(pageCount) pages"))
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - Init

    init(_ result: CompressionResult) {
        id = result.id
        kind = .compressed
        url = result.outputURL
        urls = [result.outputURL]
        tool = .compress
        detail = nil
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
        urls = [result.outputURL]
        tool = .merge
        detail = nil
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
        urls = [result.outputURL]
        tool = .split
        detail = nil
        size = result.outputSize
        date = result.timestamp
        originalSize = nil
        pageCount = result.pageCount
        sourceCount = nil
        pageRange = result.pageRange
    }

    init(_ result: ToolResult) {
        id = result.id
        kind = result.kind
        url = result.urls[0]
        urls = result.urls
        tool = result.tool
        detail = result.detail
        size = result.size
        date = result.date
        originalSize = nil
        pageCount = result.pageCount
        sourceCount = nil
        pageRange = nil
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
    }
}
