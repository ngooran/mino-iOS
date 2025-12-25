//
//  PDFCompressor.swift
//  Mino
//
//  PDF compression engine using MuPDF
//

import Foundation

// MARK: - Compression Quality Presets

/// Compression quality presets with associated parameters
enum CompressionQuality: String, CaseIterable, Identifiable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    /// JPEG quality (0-100)
    var jpegQuality: Int32 {
        switch self {
        case .low: return 30
        case .medium: return 50
        case .high: return 70
        }
    }

    /// Target DPI for image downsampling
    var targetDPI: Int32 {
        switch self {
        case .low: return 72
        case .medium: return 100
        case .high: return 150
        }
    }

    /// DPI threshold (images above this will be downsampled)
    var dpiThreshold: Int32 {
        targetDPI + 50
    }

    /// Garbage collection level (0-4)
    var garbageLevel: Int32 {
        4 // Maximum for all quality levels
    }

    /// User-friendly description
    var displayDescription: String {
        switch self {
        case .low:
            return "Maximum compression, smaller file"
        case .medium:
            return "Balanced quality and size"
        case .high:
            return "Better quality, larger file"
        }
    }

    /// Technical description
    var technicalDescription: String {
        "JPEG \(jpegQuality)%, \(targetDPI) DPI"
    }

    /// Expected compression ratio description
    var expectedReduction: String {
        switch self {
        case .low: return "85-95%"
        case .medium: return "75-85%"
        case .high: return "60-75%"
        }
    }

    /// Convert to compression settings
    var settings: CompressionSettings {
        CompressionSettings(
            jpegQuality: Int(jpegQuality),
            targetDPI: Int(targetDPI),
            garbageLevel: Int(garbageLevel),
            compressStreams: true,
            compressImages: true,
            compressFonts: true,
            cleanContent: true,
            preset: self
        )
    }
}

// MARK: - Compression Settings

/// Custom compression settings
struct CompressionSettings: Sendable {
    /// JPEG quality for image recompression (1-100, higher = better quality, larger file)
    var jpegQuality: Int

    /// Target DPI for image downsampling (72-300)
    var targetDPI: Int

    /// Garbage collection level (0-4, higher = more aggressive cleanup)
    var garbageLevel: Int

    /// Compress content streams
    var compressStreams: Bool

    /// Compress images
    var compressImages: Bool

    /// Compress fonts
    var compressFonts: Bool

    /// Clean and sanitize content streams
    var cleanContent: Bool

    /// The preset this was based on (nil if fully custom)
    var preset: CompressionQuality?

    /// DPI threshold (images above this DPI will be downsampled)
    var dpiThreshold: Int {
        targetDPI + 50
    }

    /// Default settings (Medium preset)
    static let `default` = CompressionQuality.medium.settings

    /// Initialize with all parameters
    init(
        jpegQuality: Int = 50,
        targetDPI: Int = 100,
        garbageLevel: Int = 4,
        compressStreams: Bool = true,
        compressImages: Bool = true,
        compressFonts: Bool = true,
        cleanContent: Bool = true,
        preset: CompressionQuality? = nil
    ) {
        self.jpegQuality = max(1, min(100, jpegQuality))
        self.targetDPI = max(50, min(300, targetDPI))
        self.garbageLevel = max(0, min(4, garbageLevel))
        self.compressStreams = compressStreams
        self.compressImages = compressImages
        self.compressFonts = compressFonts
        self.cleanContent = cleanContent
        self.preset = preset
    }

    /// Human-readable description
    var displayDescription: String {
        if let preset = preset {
            return preset.displayDescription
        }
        return "Custom settings"
    }

    /// Technical description
    var technicalDescription: String {
        "JPEG \(jpegQuality)%, \(targetDPI) DPI"
    }

    /// Display name for results
    var displayName: String {
        preset?.rawValue ?? "Custom"
    }
}

// MARK: - Compression Result

/// Result of a successful compression operation
struct CompressionResult: Sendable, Identifiable {
    let id: UUID
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let settings: CompressionSettings
    let duration: TimeInterval
    let timestamp: Date

    /// Convenience accessor for preset quality (if using preset)
    var quality: CompressionQuality {
        settings.preset ?? .medium
    }

    init(
        outputURL: URL,
        originalSize: Int64,
        compressedSize: Int64,
        settings: CompressionSettings,
        duration: TimeInterval
    ) {
        self.id = UUID()
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.settings = settings
        self.duration = duration
        self.timestamp = Date()
    }

    /// Legacy initializer for compatibility
    init(
        outputURL: URL,
        originalSize: Int64,
        compressedSize: Int64,
        quality: CompressionQuality,
        duration: TimeInterval
    ) {
        self.init(
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            settings: quality.settings,
            duration: duration
        )
    }

    /// Bytes saved
    var savedBytes: Int64 {
        max(0, originalSize - compressedSize)
    }

    /// Compression ratio (0.0 to 1.0, lower is better)
    var compressionRatio: Double {
        guard originalSize > 0 else { return 1.0 }
        return Double(compressedSize) / Double(originalSize)
    }

    /// Percentage reduction
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

    /// Formatted reduction percentage
    var formattedReduction: String {
        String(format: "%.1f%%", reductionPercentage)
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
    var outputFileName: String {
        outputURL.lastPathComponent
    }
}

// MARK: - PDF Compressor

/// Main PDF compression engine using MuPDF
final class PDFCompressor: @unchecked Sendable {

    // MARK: - Compression

    /// Compresses a PDF document with the specified settings
    func compress(
        documentURL: URL,
        settings: CompressionSettings,
        outputURL: URL
    ) throws -> CompressionResult {
        let startTime = Date()

        // Get original file size
        let originalSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: documentURL.path),
           let size = attrs[.size] as? Int64 {
            originalSize = size
        } else {
            originalSize = 0
        }

        // Create context
        guard let ctx = mino_create_context() else {
            throw MuPDFError.contextCreationFailed
        }
        defer { mino_drop_context(ctx) }

        // Open document
        guard let doc = mino_open_document(ctx, documentURL.path) else {
            let errorMsg = getLastError() ?? "Unknown error"
            throw MuPDFError.documentOpenFailed(path: documentURL.path, reason: errorMsg)
        }
        defer { mino_drop_document(ctx, doc) }

        // Get PDF-specific handle
        guard let pdfDoc = mino_pdf_specifics(ctx, doc) else {
            throw MuPDFError.invalidPDFDocument
        }

        // Create output directory if needed
        let outputDir = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Remove existing output file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Perform compression using C helper
        let result = mino_compress_pdf(
            ctx,
            pdfDoc,
            outputURL.path,
            Int32(settings.jpegQuality),
            Int32(settings.targetDPI),
            Int32(settings.garbageLevel)
        )

        if result != 0 {
            let errorMsg = getLastError() ?? "Unknown compression error"
            mino_clear_error()
            throw MuPDFError.compressionFailed(reason: errorMsg)
        }

        // Get compressed file size
        let compressedSize = mino_get_file_size(outputURL.path)
        if compressedSize < 0 {
            throw MuPDFError.saveFailed(reason: "Could not verify output file")
        }

        let duration = Date().timeIntervalSince(startTime)

        return CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            settings: settings,
            duration: duration
        )
    }

    /// Compresses a PDF document with the specified quality preset
    func compress(
        documentURL: URL,
        quality: CompressionQuality,
        outputURL: URL
    ) throws -> CompressionResult {
        try compress(documentURL: documentURL, settings: quality.settings, outputURL: outputURL)
    }

    private func getLastError() -> String? {
        guard let cError = mino_get_last_error() else { return nil }
        return String(cString: cError)
    }

    // MARK: - Output URL Generation

    /// Generates an output URL for a compressed PDF
    static func generateOutputURL(
        for originalURL: URL,
        settings: CompressionSettings
    ) -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Compressed", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: documentsDir,
            withIntermediateDirectories: true
        )

        let originalName = originalURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let suffix = settings.displayName.lowercased()

        return documentsDir
            .appendingPathComponent("\(originalName)_\(suffix)_\(timestamp)")
            .appendingPathExtension("pdf")
    }

    /// Generates an output URL for a compressed PDF (legacy)
    static func generateOutputURL(
        for originalURL: URL,
        quality: CompressionQuality
    ) -> URL {
        generateOutputURL(for: originalURL, settings: quality.settings)
    }
}
