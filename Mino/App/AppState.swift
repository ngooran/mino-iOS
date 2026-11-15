//
//  AppState.swift
//  Mino
//
//  Global application state: services, navigation, task sessions and Pro gating.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {

    // MARK: - Services

    let documentImporter = DocumentImporter()
    let compressionService = CompressionService()
    let batchCompressionService = BatchCompressionService()
    let mergeService = MergeService()
    let splitService = SplitService()
    let store = ProStore()
    let usage = FreeUsage()

    // MARK: - Navigation

    var selectedTab: AppTab = .home
    var homePath: [Route] = []
    var filesPath: [Route] = []
    var settingsPath: [Route] = []

    // MARK: - Sessions

    var compressSession: CompressSession?
    var mergeSession: MergeSession?
    var splitSession: SplitSession?

    // MARK: - Presentation

    /// Non-nil while the file picker is showing.
    var importTarget: ImportTarget? {
        didSet {
            if let importTarget { lastImportTarget = importTarget }
        }
    }
    /// The most recent picker target; read when the picker returns.
    private(set) var lastImportTarget: ImportTarget = .compress
    /// Non-nil while the Mino Pro sheet is showing.
    var paywallReason: PaywallReason?
    /// Message for the error alert.
    var errorMessage: String?
    /// PDFs are being copied in.
    var isImporting = false

    /// Runs after Pro is unlocked from the paywall (e.g. continue to Merge).
    private var afterUnlock: (() -> Void)?

    var isPro: Bool { store.isPro }

    /// The quality preselected for new compressions (set in Settings).
    var defaultQuality: CompressionQuality {
        CompressionQuality(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.defaultQuality) ?? "") ?? .medium
    }

    // MARK: - Files

    /// Every generated file, newest first.
    var files: [FileItem] {
        let compressed = compressionService.recentResults.map(FileItem.init)
        let merged = mergeService.recentResults.map(FileItem.init)
        let split = splitService.recentResults.map(FileItem.init)
        return (compressed + merged + split).sorted { $0.date > $1.date }
    }

    func delete(_ item: FileItem) {
        switch item.kind {
        case .compressed:
            if let result = compressionService.recentResults.first(where: { $0.id == item.id }) {
                compressionService.deleteResult(result)
            }
        case .merged:
            if let result = mergeService.recentResults.first(where: { $0.id == item.id }) {
                mergeService.deleteResult(result)
            }
        case .split:
            if let result = splitService.recentResults.first(where: { $0.id == item.id }) {
                splitService.deleteResult(result)
            }
        }
        for tab in AppTab.allCases {
            setPath(path(for: tab).filter { $0 != .preview(item) }, for: tab)
        }
    }

    // MARK: - Navigation helpers

    func path(for tab: AppTab) -> [Route] {
        switch tab {
        case .home: return homePath
        case .files: return filesPath
        case .settings: return settingsPath
        }
    }

    func setPath(_ path: [Route], for tab: AppTab) {
        switch tab {
        case .home: homePath = path
        case .files: filesPath = path
        case .settings: settingsPath = path
        }
    }

    /// Shows a route as the first screen of a tab.
    func show(_ route: Route, in tab: AppTab = .home) {
        selectedTab = tab
        if path(for: tab).first != route {
            setPath([route], for: tab)
        }
    }

    /// Closes the current task and returns to Home.
    func closeTask() {
        homePath = []
    }

    // MARK: - Pro gating

    /// Returns true when Pro is unlocked. Otherwise shows Mino Pro and
    /// remembers `action` to run once the person unlocks it.
    @discardableResult
    func requirePro(_ reason: PaywallReason, then action: (() -> Void)? = nil) -> Bool {
        if isPro { return true }
        afterUnlock = action
        paywallReason = reason
        return false
    }

    func showPaywall(_ reason: PaywallReason = .general) {
        afterUnlock = nil
        paywallReason = reason
    }

    /// Called by the paywall after a purchase or restore unlocks Pro.
    func didUnlockPro() {
        paywallReason = nil
        let action = afterUnlock
        afterUnlock = nil
        guard let action else { return }
        // Let the sheet finish dismissing before presenting anything else.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }

    func paywallDismissed() {
        afterUnlock = nil
    }

    // MARK: - Entry points

    func chooseFilesToCompress() {
        importTarget = .compress
    }

    func openMerge() {
        guard requirePro(.merge, then: { [weak self] in self?.openMerge() }) else { return }
        if mergeSession == nil || mergeSession?.phase != .configure {
            mergeSession = MergeSession()
        }
        show(.merge)
        if mergeSession?.documents.isEmpty == true {
            importTarget = .merge
        }
    }

    func openSplit() {
        guard requirePro(.split, then: { [weak self] in self?.openSplit() }) else { return }
        importTarget = .split
    }

    func addFilesToMerge() {
        importTarget = .merge
    }

    func chooseFileToSplit() {
        importTarget = .split
    }

    // MARK: - Import

    func handleImporterResult(_ result: Result<[URL], Error>, target: ImportTarget) {
        switch result {
        case .success(let urls):
            Task { await importAndRoute(urls, target: target) }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// PDFs arriving from drag and drop, "Open in Mino" or the share extension.
    /// They go to Merge when the merge screen is open, otherwise to Compress.
    func handleIncoming(_ urls: [URL]) {
        Task { await receive(urls) }
    }

    /// Imports incoming PDFs and opens the right screen. Returns when the copies are made.
    func receive(_ urls: [URL]) async {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        let mergeIsOpen = selectedTab == .home && homePath.last == .merge && mergeSession?.phase == .configure
        await importAndRoute(pdfs, target: mergeIsOpen ? .merge : .compress)
    }

    private func importAndRoute(_ urls: [URL], target: ImportTarget) async {
        isImporting = true
        defer { isImporting = false }

        var documents: [PDFDocumentInfo] = []
        var failures: [String] = []
        for url in urls {
            do {
                documents.append(try await documentImporter.importDocument(from: url))
            } catch {
                failures.append(url.deletingPathExtension().lastPathComponent)
            }
        }
        if !failures.isEmpty {
            errorMessage = failures.count == 1
                ? "“\(failures[0])” couldn't be opened. Make sure it's a PDF that isn't password protected."
                : "\(failures.count) files couldn't be opened. Make sure they're PDFs that aren't password protected."
        }
        guard !documents.isEmpty else { return }

        switch target {
        case .compress:
            startCompressSession(with: documents)
        case .merge:
            if !isPro {
                requirePro(.merge) { [weak self] in self?.addToMerge(documents) }
                return
            }
            addToMerge(documents)
        case .split:
            if !isPro {
                requirePro(.split) { [weak self] in self?.startSplitSession(with: documents[0]) }
                return
            }
            startSplitSession(with: documents[0])
        }
    }

    private func addToMerge(_ documents: [PDFDocumentInfo]) {
        if mergeSession == nil || mergeSession?.phase != .configure {
            mergeSession = MergeSession()
        }
        mergeSession?.documents.append(contentsOf: documents)
        show(.merge)
    }

    private func startSplitSession(with document: PDFDocumentInfo) {
        splitSession?.task?.cancel()
        splitSession = SplitSession(document: document)
        show(.split)
    }

    // MARK: - Compress

    func startCompressSession(with documents: [PDFDocumentInfo]) {
        guard !documents.isEmpty else { return }
        if documents.count > 1 && !isPro {
            requirePro(.batch) { [weak self] in self?.startCompressSession(with: documents) }
            return
        }
        compressSession?.estimateTask?.cancel()
        let session = CompressSession(documents: documents, quality: defaultQuality)
        compressSession = session
        show(.compress)
        startEstimates(for: session)
    }

    /// Compresses a short sample to show expected sizes next to each preset.
    private func startEstimates(for session: CompressSession) {
        guard session.documents.count == 1, let document = session.documents.first else { return }
        var sampleRange: PageRange?
        if document.pageCount > 4 {
            let start = max(1, document.pageCount / 2 - 1)
            sampleRange = PageRange(start: start, end: min(document.pageCount, start + 3))
        }
        let presets = CompressionQuality.allCases.map { (key: $0.rawValue, settings: $0.settings) }
        let compressor = PDFCompressor()
        let splitter = PDFSplitter()
        let url = document.url
        let fileSize = document.fileSize

        session.isEstimating = true
        session.estimateTask = Task { [weak session] in
            let values = await Task.detached(priority: .utility) {
                SizeEstimator.estimate(
                    documentURL: url,
                    fileSize: fileSize,
                    sampleRange: sampleRange,
                    presets: presets,
                    compressor: compressor,
                    splitter: splitter
                )
            }.value
            guard let session, !Task.isCancelled else { return }
            var estimates: [CompressionQuality: Int64] = [:]
            for (key, value) in values {
                if let quality = CompressionQuality(rawValue: key) {
                    estimates[quality] = value
                }
            }
            session.estimates = estimates
            session.isEstimating = false
        }
    }

    /// Batch progress (0...1) while several PDFs compress.
    var batchProgress: (done: Int, total: Int)? {
        guard let queue = batchCompressionService.currentQueue, batchCompressionService.isProcessing else { return nil }
        return (queue.completedCount, queue.count)
    }

    func compress(_ session: CompressSession) {
        if session.isBatch && !isPro {
            requirePro(.batch) { [weak self] in self?.compress(session) }
            return
        }
        if !isPro && usage.remaining == 0 {
            requirePro(.dailyLimit) { [weak self] in self?.compress(session) }
            return
        }
        if session.choice == .custom && !isPro {
            session.choice = .preset(.medium)
        }

        let settings = session.settings
        let documents = session.documents
        session.wasCancelled = false
        session.phase = .working
        HapticManager.shared.compressionStart()

        Task {
            do {
                let results: [CompressionResult]
                if documents.count == 1 {
                    results = [try await compressionService.compress(document: documents[0], settings: settings)]
                    if session.wasCancelled {
                        results.forEach { compressionService.deleteResult($0) }
                        return
                    }
                } else {
                    results = try await batchCompressionService.startBatch(documents: documents, settings: settings)
                    if session.wasCancelled {
                        results.forEach { OutputLocation.removeFile(at: $0.outputURL) }
                        return
                    }
                    results.reversed().forEach { compressionService.addBatchResult($0) }
                }

                guard !results.isEmpty else {
                    session.phase = .failed("None of the PDFs could be compressed. They may be damaged or password protected.")
                    HapticManager.shared.error()
                    return
                }

                for result in results {
                    HistoryManager.shared.addEntry(from: result, originalFileName: FileItem(result).name)
                    HistoryManager.shared.recordGoodCompression(reductionPercentage: result.reductionPercentage)
                }
                if !isPro { usage.recordUse() }

                session.results = results
                session.phase = .done
                HapticManager.shared.compressionComplete()
                HistoryManager.shared.requestReviewIfAppropriate()
            } catch {
                guard !session.wasCancelled else { return }
                session.phase = .failed(error.localizedDescription)
                HapticManager.shared.error()
            }
        }
    }

    func cancelCompression(_ session: CompressSession) {
        session.wasCancelled = true
        if session.isBatch {
            batchCompressionService.cancelBatch()
        }
        session.phase = .configure
    }

    // MARK: - Merge

    var mergeProgress: Double {
        mergeService.currentJob?.state.progress ?? 0
    }

    func merge(_ session: MergeSession) {
        guard session.documents.count >= 2 else { return }
        guard requirePro(.merge, then: { [weak self] in self?.merge(session) }) else { return }
        session.phase = .working
        let documents = session.documents
        Task {
            do {
                let result = try await mergeService.merge(
                    documents: documents,
                    outputName: PDFMerger.suggestedOutputName(from: documents)
                )
                session.result = result
                session.phase = .done
                HapticManager.shared.compressionComplete()
                HistoryManager.shared.recordGoodMerge()
                HistoryManager.shared.requestReviewIfAppropriate()
            } catch {
                session.phase = .failed(error.localizedDescription)
                HapticManager.shared.error()
            }
        }
    }

    // MARK: - Split

    func split(_ session: SplitSession) {
        guard requirePro(.split, then: { [weak self] in self?.split(session) }) else { return }
        if session.mode == .choosePages && session.selectedPages.isEmpty { return }
        session.phase = .working
        session.completedPages = 0
        session.task = Task {
            do {
                switch session.mode {
                case .choosePages:
                    let result = try await splitService.extractPages(
                        from: session.document,
                        pages: Array(session.selectedPages)
                    )
                    session.results = [result]
                case .everyPage:
                    session.results = try await splitService.splitEveryPage(of: session.document) { done, _ in
                        session.completedPages = done
                    }
                }
                session.phase = .done
                HapticManager.shared.compressionComplete()
                HistoryManager.shared.recordGoodSplit()
                HistoryManager.shared.requestReviewIfAppropriate()
            } catch is CancellationError {
                session.phase = .configure
            } catch {
                session.phase = .failed(error.localizedDescription)
                HapticManager.shared.error()
            }
        }
    }

    func cancelSplit(_ session: SplitSession) {
        session.task?.cancel()
        session.phase = .configure
    }
}

/// Keys for values stored with @AppStorage.
enum SettingsKeys {
    static let defaultQuality = "defaultQuality"
    static let appearance = "appearance"
}
