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
        case .low: return String(localized: "Smallest")
        case .medium: return String(localized: "Balanced")
        case .high: return String(localized: "Best Quality")
        }
    }

    /// What the preset is good for.
    var useCase: String {
        switch self {
        case .low: return String(localized: "for messages and uploads")
        case .medium: return String(localized: "good for email")
        case .high: return String(localized: "for printing")
        }
    }
}

// MARK: - Shared task state

/// Progress and outcome of one run of a tool. Every session of the tools
/// added after 2.0 owns one, and `AppState.run` drives it.
@Observable
@MainActor
final class TaskState {
    var phase: TaskPhase = .configure
    /// 0...1 while working, or nil when the tool can't tell.
    var progress: Double?
    var result: FileItem?
    /// Text the tool recognized or extracted, for the result screen.
    var resultText: String?
    var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
    }
}

/// A session of a tool that runs through `AppState.run`.
@MainActor
protocol ToolSession: AnyObject {
    var state: TaskState { get }
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

// MARK: - Scan to PDF

@Observable
@MainActor
final class ScanSession: ToolSession {
    let state = TaskState()
    var pages: [ScanPage] = []
    var filter: ScanFilter
    let quality: CompressionQuality
    /// Run text recognition on the scan (Mino Pro).
    var makeSearchable = false
    /// Captured pages are being saved.
    var isLoading = false

    init(quality: CompressionQuality) {
        self.quality = quality
        filter = ScanFilter(rawValue: StorageRoot.defaults.string(forKey: SettingsKeys.scanFilter) ?? "") ?? .color
    }

    /// Drag and drop: the dragged page takes the place of the one it is dropped on.
    func move(_ id: ScanPage.ID, to target: ScanPage.ID) {
        guard id != target,
              let from = pages.firstIndex(where: { $0.id == id }),
              let to = pages.firstIndex(where: { $0.id == target }) else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: to)
    }
}

// MARK: - Recognize Text

@Observable
@MainActor
final class OCRSession: ToolSession {

    enum Output: Hashable {
        case searchablePDF
        case text
    }

    let state = TaskState()
    let document: PDFDocumentInfo
    var output: Output = .searchablePDF
    /// A Vision language code, or nil to detect the language.
    var language: String?

    init(document: PDFDocumentInfo) {
        self.document = document
    }
}

// MARK: - Office to PDF

@Observable
@MainActor
final class OfficeSession: ToolSession {
    let state = TaskState()
    /// A copy of the chosen file in the working folder.
    let fileURL: URL
    let fileSize: Int64
    var pageSize: OfficePageSize

    init(fileURL: URL) {
        self.fileURL = fileURL
        fileSize = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int64) ?? 0
        pageSize = OfficePageSize(rawValue: StorageRoot.defaults.string(forKey: SettingsKeys.officePageSize) ?? "") ?? .regional
    }

    var name: String { fileURL.deletingPathExtension().lastPathComponent }

    /// "DOCX", "XLS", ...
    var typeBadge: String { fileURL.pathExtension.uppercased() }

    /// What kind of document it is, in words.
    var typeName: String {
        switch fileURL.pathExtension.lowercased() {
        case "doc", "docx": return String(localized: "Word document")
        case "xls", "xlsx": return String(localized: "Excel workbook")
        case "ppt", "pptx": return String(localized: "PowerPoint presentation")
        case "rtf": return String(localized: "Rich text document")
        case "csv": return String(localized: "CSV table")
        case "htm", "html": return String(localized: "Web page")
        default: return String(localized: "Text document")
        }
    }
}

// MARK: - Photos to PDF

@Observable
@MainActor
final class PhotosToPDFSession: ToolSession {
    let state = TaskState()
    var photos: [PhotoInput] = []
    var pageSize: PhotoPageSize
    var margin: PhotoMargin = .none
    /// Photos are being copied in from the picker.
    var isLoading = false

    init() {
        pageSize = PhotoPageSize(rawValue: StorageRoot.defaults.string(forKey: SettingsKeys.photoPageSize) ?? "") ?? .fit
    }

    /// Drag and drop: the dragged photo takes the place of the one it is dropped on.
    func move(_ id: PhotoInput.ID, to target: PhotoInput.ID) {
        guard id != target,
              let from = photos.firstIndex(where: { $0.id == id }),
              let to = photos.firstIndex(where: { $0.id == target }) else { return }
        let photo = photos.remove(at: from)
        photos.insert(photo, at: to)
    }
}

// MARK: - PDF to Images

@Observable
@MainActor
final class PDFToImagesSession: ToolSession {

    enum Scope: Hashable {
        case all
        case choose
    }

    let state = TaskState()
    let document: PDFDocumentInfo
    var scope: Scope = .all
    var selectedPages: Set<Int> = []
    var format: ImageFormat = .jpg
    var resolution: ImageResolution = .standard

    init(document: PDFDocumentInfo) {
        self.document = document
    }

    /// 1-based pages to export, in order.
    var pages: [Int] {
        switch scope {
        case .all: return Array(1...max(1, document.pageCount))
        case .choose: return selectedPages.sorted()
        }
    }
}

// MARK: - Organize Pages

@Observable
@MainActor
final class OrganizeSession: ToolSession {
    let state = TaskState()
    let document: PDFDocumentInfo
    var pages: [OrganizedPage]
    var selection: Set<OrganizedPage.ID> = []
    /// PDFs whose pages were inserted, kept so their thumbnails can load.
    var insertedDocuments: [PDFDocumentInfo] = []

    init(document: PDFDocumentInfo) {
        self.document = document
        pages = (0..<max(1, document.pageCount)).map { OrganizedPage(source: .original($0)) }
    }

    var hasChanges: Bool {
        pages.count != document.pageCount
            || pages.enumerated().contains { index, page in page.source != .original(index) || page.rotation != 0 }
    }

    private var selectedIndices: [Int] {
        pages.indices.filter { selection.contains(pages[$0].id) }
    }

    func toggle(_ page: OrganizedPage) {
        if selection.contains(page.id) {
            selection.remove(page.id)
        } else {
            selection.insert(page.id)
        }
    }

    func rotateSelection() {
        for index in selectedIndices {
            pages[index].rotation = (pages[index].rotation + 90) % 360
        }
    }

    func deleteSelection() {
        // A PDF needs at least one page.
        guard selection.count < pages.count else { return }
        pages.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func duplicateSelection() {
        for index in selectedIndices.reversed() {
            var copy = pages[index]
            copy.id = UUID()
            pages.insert(copy, at: index + 1)
        }
    }

    /// Moves the selected pages one place toward the start (-1) or the end (+1).
    func moveSelection(by direction: Int) {
        let indices = direction < 0 ? selectedIndices : selectedIndices.reversed()
        var settled: Set<Int> = []
        for index in indices {
            let target = index + direction
            guard pages.indices.contains(target), !settled.contains(target) else {
                settled.insert(index)
                continue
            }
            pages.swapAt(index, target)
            settled.insert(target)
        }
    }

    /// Drag and drop: the dragged page takes the place of the one it is dropped on.
    func move(_ id: OrganizedPage.ID, to target: OrganizedPage.ID) {
        guard id != target,
              let from = pages.firstIndex(where: { $0.id == id }),
              let to = pages.firstIndex(where: { $0.id == target }) else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: to)
    }

    /// Where new pages go: after the last selected page, or at the end.
    private var insertionIndex: Int {
        (selectedIndices.last.map { $0 + 1 }) ?? pages.count
    }

    func insertBlankPage() {
        // Match the page it follows, or the first page.
        let size = document.firstPageSize ?? CGSize(width: 595, height: 842)
        pages.insert(OrganizedPage(source: .blank(width: size.width, height: size.height)), at: insertionIndex)
    }

    func insertPages(of other: PDFDocumentInfo) {
        insertedDocuments.append(other)
        let new = (0..<other.pageCount).map { OrganizedPage(source: .external(url: other.url, page: $0)) }
        pages.insert(contentsOf: new, at: insertionIndex)
    }
}

// MARK: - Protect & Unlock

@Observable
@MainActor
final class ProtectSession: ToolSession {

    enum Mode: Hashable {
        case protect
        case unlock
    }

    let state = TaskState()
    let document: PDFDocumentInfo
    var mode: Mode
    var password = ""
    var confirmation = ""
    var allowPrinting = true
    var allowCopying = true
    /// Unlock, for a PDF that opens freely but restricts printing or copying.
    var permissionsPassword = ""

    init(document: PDFDocumentInfo) {
        self.document = document
        mode = document.wasLocked || document.hasRestrictions ? .unlock : .protect
    }

    var passwordsMatch: Bool { !password.isEmpty && password == confirmation }

    /// False when the password has characters that don't work in every PDF app.
    var passwordIsPortable: Bool { PDFProtector.isPortable(password) }

    var canRun: Bool {
        switch mode {
        case .protect: return passwordsMatch && passwordIsPortable
        case .unlock: return document.wasLocked || (document.hasRestrictions && !permissionsPassword.isEmpty)
        }
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
