//
//  CompressionHistory.swift
//  Mino
//
//  Model for compression history entries
//

import Foundation

/// A single compression history entry
struct CompressionHistoryEntry: Codable, Identifiable {
    let id: UUID
    let originalFileName: String
    let originalSize: Int64
    let compressedSize: Int64
    let timestamp: Date
    let duration: TimeInterval
    let qualityUsed: String

    init(
        originalFileName: String,
        originalSize: Int64,
        compressedSize: Int64,
        duration: TimeInterval,
        qualityUsed: String
    ) {
        self.id = UUID()
        self.originalFileName = originalFileName
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.timestamp = Date()
        self.duration = duration
        self.qualityUsed = qualityUsed
    }

    /// Bytes saved
    var savedBytes: Int64 {
        max(0, originalSize - compressedSize)
    }

    /// Reduction percentage
    var reductionPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }

    /// Formatted original size
    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    /// Formatted compressed size
    var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }

    /// Formatted saved bytes
    var formattedSavedBytes: String {
        ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
    }

    /// Formatted reduction
    var formattedReduction: String {
        String(format: "%.1f%%", reductionPercentage)
    }

    /// Formatted timestamp
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
