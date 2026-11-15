//
//  AppState.swift
//  Mino
//
//  Global application state: services, navigation, task sessions and Pro gating.
//

import Foundation
import SwiftUI
import UIKit

@Observable
@MainActor
final class AppState {

    // MARK: - Services

    let documentImporter = DocumentImporter()
    let compressionService = CompressionService()
    let batchCompressionService = BatchCompressionService()
    let mergeService = MergeService()
    let splitService = SplitService()
    /// Results of the tools added after 2.0.
    let toolResults = ToolResultStore()
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
    var scanSession: ScanSession?
    var ocrSession: OCRSession?
    var photosSession: PhotosToPDFSession?
    var imagesSession: PDFToImagesSession?
    var organizeSession: OrganizeSession?
    var protectSession: ProtectSession?

    // MARK: - Presentation

    /// Non-nil while the file picker is showing.
    var importTarget: ImportTarget? {
        didSet {
            if let importTarget { lastImportTarget = importTarget }
        }
    }
    /// The most recent picker target; read when the picker returns.
    private(set) var lastImportTarget: ImportTarget = .open
    /// Text in the Home search field.
    var toolQuery = ""
    /// Non-nil while the "What do you want to do?" sheet is showing.
    var toolPicker: ToolPickerContext?
    /// Non-nil while the password prompt for a locked PDF is showing.
    var passwordRequest: PasswordRequest?
    private var passwordContinuation: CheckedContinuation<String?, Never>?
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
        CompressionQuality(rawValue: StorageRoot.defaults.string(forKey: SettingsKeys.defaultQuality) ?? "") ?? .medium
    }

    // MARK: - Files

    /// Every generated file, newest first.
    var files: [FileItem] {
        let compressed = compressionService.recentResults.map(FileItem.init)
        let merged = mergeService.recentResults.map(FileItem.init)
        let split = splitService.recentResults.map(FileItem.init)
        let tools = toolResults.results.map(FileItem.init)
        return (compressed + merged + split + tools).sorted { $0.date > $1.date }
    }

    func delete(_ item: FileItem) {
        if let result = compressionService.recentResults.first(where: { $0.id == item.id }) {
            compressionService.deleteResult(result)
        } else if let result = mergeService.recentResults.first(where: { $0.id == item.id }) {
            mergeService.deleteResult(result)
        } else if let result = splitService.recentResults.first(where: { $0.id == item.id }) {
            splitService.deleteResult(result)
        } else {
            toolResults.delete(id: item.id)
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

    /// Opens a tool from Home, search or a menu. Tools that need a file ask for one first.
    func open(_ tool: Tool) {
        switch tool {
        case .merge:
            openMerge()
        case .photosToPDF:
            openPhotosToPDF()
        case .scan:
            openScan()
        default:
            importTarget = .tool(tool)
        }
    }

    /// "Open PDF": choose a file, then a tool.
    func openPDF() {
        importTarget = .open
    }

    /// Starts a tool with PDFs that are already imported.
    func start(_ tool: Tool, with documents: [PDFDocumentInfo]) {
        guard let first = documents.first else { return }
        switch tool {
        case .compress:
            startCompressSession(with: documents)
        case .merge:
            addToMerge(documents)
        case .split:
            startSplitSession(with: first)
        case .pdfToImages:
            imagesSession?.state.cancel()
            imagesSession = PDFToImagesSession(document: first)
            show(tool.route)
        case .organize:
            organizeSession?.state.cancel()
            organizeSession = OrganizeSession(document: first)
            show(tool.route)
        case .protect:
            protectSession?.state.cancel()
            protectSession = ProtectSession(document: first)
            show(tool.route)
        case .ocr:
            ocrSession?.state.cancel()
            ocrSession = OCRSession(document: first)
            show(tool.route)
        case .photosToPDF, .scan, .officeToPDF, .fillSign, .edit, .pdfToWord:
            break
        }
    }

    func chooseFilesToCompress() {
        importTarget = .tool(.compress)
    }

    func openMerge() {
        if mergeSession == nil || mergeSession?.phase != .configure {
            mergeSession = MergeSession()
        }
        show(.merge)
        if mergeSession?.documents.isEmpty == true {
            importTarget = .mergeAdd
        }
    }

    func openSplit() {
        importTarget = .tool(.split)
    }

    func addFilesToMerge() {
        importTarget = .mergeAdd
    }

    func chooseFileToSplit() {
        importTarget = .tool(.split)
    }

    // MARK: - Tool picker

    /// Shows "What do you want to do?" for imported PDFs.
    func showToolPicker(for documents: [PDFDocumentInfo]) {
        guard !documents.isEmpty else { return }
        toolPicker = ToolPickerContext(documents: documents)
    }

    /// Shows the tool picker for a generated PDF (Files, or "Continue with another tool").
    func showToolPicker(for item: FileItem) {
        guard item.isPDF else { return }
        Task {
            let documents = await importDocuments([item.url])
            showToolPicker(for: documents)
        }
    }

    /// Runs when a tool is chosen in the picker sheet.
    func pick(_ tool: Tool, from context: ToolPickerContext) {
        toolPicker = nil
        start(tool, with: tool == .compress || tool == .merge ? context.documents : Array(context.documents.prefix(1)))
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

    /// Files arriving from drag and drop, "Open in Mino" or the share extension.
    func handleIncoming(_ urls: [URL]) {
        Task { await receive(urls) }
    }

    /// Imports incoming files and opens the right screen. Returns when the copies are made.
    /// - PDFs join the merge list when it is open; otherwise the tool picker shows.
    /// - Images go to Photos to PDF.
    func receive(_ urls: [URL]) async {
        let pdfs = urls.filter { ImportTypes.classify($0) == .pdf }
        let images = urls.filter { ImportTypes.classify($0) == .image }

        if !pdfs.isEmpty {
            let mergeIsOpen = selectedTab == .home && homePath.last == .merge && mergeSession?.phase == .configure
            await importAndRoute(pdfs, target: mergeIsOpen ? .mergeAdd : .open)
        } else if !images.isEmpty, Tool.photosToPDF.isAvailable {
            await importAndRoute(images, target: .tool(.photosToPDF))
        }
    }

    private func importAndRoute(_ urls: [URL], target: ImportTarget) async {
        if target == .tool(.photosToPDF) {
            openPhotosToPDF(askingForPhotos: false)
            await addPhotos(from: urls)
            return
        }

        let documents = await importDocuments(urls)
        guard !documents.isEmpty else { return }

        switch target {
        case .open:
            showToolPicker(for: documents)
        case .mergeAdd:
            addToMerge(documents)
        case .insertPages:
            organizeSession?.insertPages(of: documents[0])
        case .tool(let tool):
            start(tool, with: documents)
        }
    }

    /// Copies PDFs in, asking for the password of each locked one. Files that
    /// can't be opened are reported in one alert.
    func importDocuments(_ urls: [URL]) async -> [PDFDocumentInfo] {
        isImporting = true
        defer { isImporting = false }

        var documents: [PDFDocumentInfo] = []
        var failures: [String] = []
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            do {
                documents.append(try await documentImporter.importDocument(from: url))
            } catch ImportError.passwordRequired(let copy) {
                isImporting = false
                if let document = await unlock(copy: copy, name: name) {
                    documents.append(document)
                }
                isImporting = true
            } catch {
                failures.append(name)
            }
        }
        if !failures.isEmpty {
            errorMessage = failures.count == 1
                ? String(localized: "“\(failures[0])” couldn't be opened. Make sure it's a PDF that isn't damaged.")
                : String(localized: "\(failures.count) files couldn't be opened. Make sure they're PDFs that aren't damaged.")
        }
        return documents
    }

    // MARK: - Locked PDFs

    /// Asks for the password until it is right or the person cancels.
    private func unlock(copy: URL, name: String) async -> PDFDocumentInfo? {
        var failed = false
        while true {
            guard let password = await askPassword(fileName: name, failed: failed) else {
                documentImporter.discard(copy: copy)
                return nil
            }
            do {
                return try await documentImporter.unlock(copy: copy, password: password)
            } catch ImportError.wrongPassword {
                failed = true
                // Let the alert finish closing before it shows again.
                try? await Task.sleep(for: .milliseconds(350))
            } catch {
                documentImporter.discard(copy: copy)
                errorMessage = String(localized: "“\(name)” couldn't be unlocked.")
                return nil
            }
        }
    }

    private func askPassword(fileName: String, failed: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            passwordContinuation = continuation
            passwordRequest = PasswordRequest(fileName: fileName, failed: failed)
        }
    }

    /// Called by the password prompt. Nil cancels.
    func submitPassword(_ password: String?) {
        passwordRequest = nil
        let continuation = passwordContinuation
        passwordContinuation = nil
        continuation?.resume(returning: password)
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

    // MARK: - Running tools

    /// Checks whether the person may run `tool` now. When not, shows Mino Pro
    /// and remembers `retry` for after the purchase.
    func mayRun(_ tool: Tool, extra: PaywallReason? = nil, retry: @escaping () -> Void) -> Bool {
        if isPro { return true }
        if tool.access == .pro {
            return requirePro(.tool(tool), then: retry)
        }
        if let extra {
            return requirePro(extra, then: retry)
        }
        if usage.remaining == 0 {
            return requirePro(.dailyLimit, then: retry)
        }
        return true
    }

    /// Runs a tool's engine off the main thread and files its result.
    ///
    /// The caller checks `mayRun` first. `work` receives a progress callback
    /// (0...1) and returns the files it wrote.
    func run(
        _ tool: Tool,
        state: TaskState,
        work: @escaping @Sendable (_ progress: @escaping @Sendable (Double) -> Void) throws -> ToolOutput
    ) {
        state.phase = .working
        state.progress = nil
        state.result = nil
        state.resultText = nil
        HapticManager.shared.compressionStart()

        state.task = Task {
            let worker = Task.detached(priority: .userInitiated) {
                try work { value in
                    Task { @MainActor in
                        if state.phase == .working { state.progress = value }
                    }
                }
            }
            let outcome = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                worker.cancel()
            }

            switch outcome {
            case .success(let output):
                if Task.isCancelled {
                    output.urls.forEach(OutputLocation.removeFile(at:))
                    state.phase = .configure
                    return
                }
                let result = toolResults.add(output, tool: tool)
                state.result = FileItem(result)
                state.resultText = output.text
                state.phase = .done
                if !isPro { usage.recordUse() }
                HapticManager.shared.compressionComplete()
                HistoryManager.shared.recordGoodOperation()
                HistoryManager.shared.requestReviewIfAppropriate()
            case .failure(let error):
                if error is CancellationError || Task.isCancelled {
                    state.phase = .configure
                } else {
                    state.phase = .failed(error.localizedDescription)
                    HapticManager.shared.error()
                }
            }
        }
    }

    /// Closes a finished or abandoned tool and returns to Home.
    func finish(_ tool: Tool) {
        switch tool {
        case .scan: scanSession = nil
        case .ocr: ocrSession = nil
        case .photosToPDF: photosSession = nil
        case .pdfToImages: imagesSession = nil
        case .organize: organizeSession = nil
        case .protect: protectSession = nil
        case .merge: mergeSession = nil
        case .split: splitSession = nil
        default: break
        }
        closeTask()
    }

    // MARK: - Scan to PDF

    func openScan() {
        if scanSession == nil || scanSession?.state.phase != .configure {
            scanSession = ScanSession(quality: defaultQuality)
        }
        show(Tool.scan.route)
    }

    /// Saves pages from the document camera and appends them, or replaces
    /// one page when it is being retaken.
    func addScannedImages(_ images: [UIImage], replacing page: ScanPage.ID? = nil) async {
        guard let session = scanSession, !images.isEmpty else { return }
        session.isLoading = true
        defer { session.isLoading = false }
        let folder = OutputLocation.workingDirectory()
        let urls = await Task.detached(priority: .userInitiated) {
            images.enumerated().compactMap { index, image -> URL? in
                let url = folder.appendingPathComponent("page-\(index).jpg")
                guard let data = image.jpegData(compressionQuality: 0.92), (try? data.write(to: url)) != nil else { return nil }
                return url
            }
        }.value
        addScanFiles(urls, replacing: page)
    }

    /// Adds page images that are already files (photos, sample pages).
    func addScanFiles(_ urls: [URL], replacing page: ScanPage.ID? = nil) {
        guard let session = scanSession else { return }
        let pages = urls.map { ScanPage(url: $0) }
        if let page, let index = session.pages.firstIndex(where: { $0.id == page }), let first = pages.first {
            session.pages[index] = first
        } else {
            session.pages.append(contentsOf: pages)
        }
    }

    func saveScan(_ session: ScanSession) {
        guard !session.pages.isEmpty else { return }
        // Scanning is free; making the scan searchable is part of Mino Pro.
        let searchable = session.makeSearchable && Tool.ocr.isAvailable
        guard mayRun(.scan, extra: searchable ? .searchableScan : nil, retry: { [weak self] in self?.saveScan(session) }) else { return }
        let pages = session.pages.map(\.url)
        let filter = session.filter
        let quality = session.quality
        let name = String(localized: "Scan \(OutputLocation.shortDate())")
        run(.scan, state: session.state) { progress in
            let output = OutputLocation.url(folder: "Scans", fileName: name)
            do {
                guard searchable else {
                    let count = try ScanEngine.makePDF(pages: pages, filter: filter, quality: quality, outputURL: output, progress: progress)
                    return ToolOutput(urls: [output], kind: .scanned, pageCount: count)
                }
                // Build the scan, then read it and add the text layer.
                let plain = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString).pdf")
                defer { try? FileManager.default.removeItem(at: plain) }
                let count = try ScanEngine.makePDF(pages: pages, filter: filter, quality: quality, outputURL: plain) { progress($0 * 0.3) }
                let recognized = try TextRecognizer.recognize(documentURL: plain) { progress(0.3 + $0 * 0.7) }
                try TextRecognizer.makeSearchablePDF(documentURL: plain, pages: recognized, outputURL: output)
                return ToolOutput(
                    urls: [output], kind: .scanned, pageCount: count,
                    detail: String(localized: "Searchable"), text: TextRecognizer.text(of: recognized)
                )
            } catch {
                OutputLocation.removeFile(at: output)
                throw error
            }
        }
    }

    // MARK: - Recognize Text

    func recognizeText(_ session: OCRSession) {
        guard mayRun(.ocr, retry: { [weak self] in self?.recognizeText(session) }) else { return }
        let document = session.document
        let language = session.language
        let wantsPDF = session.output == .searchablePDF
        run(.ocr, state: session.state) { progress in
            let output = wantsPDF
                ? OutputLocation.url(folder: "Scans", fileName: String(localized: "\(document.name) (searchable)"))
                : OutputLocation.url(folder: "Converted", fileName: document.name, fileExtension: "txt")
            do {
                let pages = try TextRecognizer.recognize(documentURL: document.url, language: language, progress: progress)
                let text = TextRecognizer.text(of: pages)
                if wantsPDF {
                    try TextRecognizer.makeSearchablePDF(documentURL: document.url, pages: pages, outputURL: output)
                    return ToolOutput(
                        urls: [output], kind: .scanned, pageCount: pages.count,
                        detail: String(localized: "Searchable"), text: text
                    )
                }
                guard !text.isEmpty else {
                    throw MuPDFError.unknownError(String(localized: "No text was found in this PDF."))
                }
                MuPDF.prepareOutput(output)
                try text.write(to: output, atomically: true, encoding: .utf8)
                return ToolOutput(urls: [output], kind: .converted, pageCount: pages.count, detail: String(localized: "Text"), text: text)
            } catch {
                OutputLocation.removeFile(at: output)
                throw error
            }
        }
    }

    // MARK: - Photos to PDF

    func openPhotosToPDF(askingForPhotos: Bool = true) {
        if photosSession == nil || photosSession?.state.phase != .configure {
            photosSession = PhotosToPDFSession()
        }
        show(Tool.photosToPDF.route)
    }

    /// Copies image files in and appends them to the photo list.
    func addPhotos(from urls: [URL]) async {
        guard let session = photosSession else { return }
        session.isLoading = true
        defer { session.isLoading = false }
        var skipped = 0
        for url in urls {
            guard let copy = try? await documentImporter.importFile(from: url) else {
                skipped += 1
                continue
            }
            if let photo = await Task.detached(operation: { PhotoInput.load(from: copy) }).value {
                session.photos.append(photo)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            errorMessage = String(localized: "\(skipped) files aren't images Mino can read, so they were left out.")
        }
    }

    /// Adds images that are already inside the working folder (from the photo picker).
    func addPhotoFiles(_ urls: [URL]) async {
        guard let session = photosSession else { return }
        for url in urls {
            if let photo = await Task.detached(operation: { PhotoInput.load(from: url) }).value {
                session.photos.append(photo)
            }
        }
    }

    func createPDF(_ session: PhotosToPDFSession) {
        guard !session.photos.isEmpty else { return }
        guard mayRun(.photosToPDF, retry: { [weak self] in self?.createPDF(session) }) else { return }
        let photos = session.photos
        let pageSize = session.pageSize
        let margin = session.margin
        let name = String(localized: "Photos \(OutputLocation.shortDate())")
        run(.photosToPDF, state: session.state) { progress in
            let output = OutputLocation.url(folder: "Converted", fileName: name)
            do {
                let pages = try PhotosToPDFEngine.makePDF(
                    photos: photos, pageSize: pageSize, margin: margin, outputURL: output, progress: progress
                )
                return ToolOutput(urls: [output], kind: .converted, pageCount: pages)
            } catch {
                OutputLocation.removeFile(at: output)
                throw error
            }
        }
    }

    // MARK: - PDF to Images

    func exportImages(_ session: PDFToImagesSession) {
        let pages = session.pages
        guard !pages.isEmpty else { return }
        guard mayRun(.pdfToImages, retry: { [weak self] in self?.exportImages(session) }) else { return }
        let document = session.document
        let format = session.format
        let dpi = session.resolution.dpi
        run(.pdfToImages, state: session.state) { progress in
            let directory = OutputLocation.directory(folder: "Images")
            do {
                let urls = try PDFToImagesEngine.export(
                    documentURL: document.url, pages: pages, format: format, dpi: dpi,
                    baseName: document.name, directory: directory, progress: progress
                )
                let detail = String(localized: "\(urls.count) \(format.title) images")
                return ToolOutput(urls: urls, kind: .converted, pageCount: urls.count, detail: detail)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }

    // MARK: - Organize Pages

    func addPagesToOrganize() {
        importTarget = .insertPages
    }

    /// Turns freshly scanned pages into a PDF and inserts its pages.
    func insertScannedPages(_ images: [UIImage], into session: OrganizeSession) async {
        guard !images.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        let folder = OutputLocation.workingDirectory()
        let quality = defaultQuality
        let filter = ScanFilter(rawValue: StorageRoot.defaults.string(forKey: SettingsKeys.scanFilter) ?? "") ?? .color
        let scan = await Task.detached(priority: .userInitiated) { () -> URL? in
            let pages = images.enumerated().compactMap { index, image -> URL? in
                let url = folder.appendingPathComponent("page-\(index).jpg")
                guard let data = image.jpegData(compressionQuality: 0.92), (try? data.write(to: url)) != nil else { return nil }
                return url
            }
            let output = folder.appendingPathComponent("Scan.pdf")
            guard (try? ScanEngine.makePDF(pages: pages, filter: filter, quality: quality, outputURL: output)) != nil else { return nil }
            return output
        }.value
        guard let scan else {
            errorMessage = String(localized: "The scanned pages couldn't be added.")
            return
        }
        session.insertPages(of: PDFDocumentInfo(url: scan, pageCount: images.count))
    }

    func saveOrganized(_ session: OrganizeSession) {
        guard !session.pages.isEmpty else { return }
        guard mayRun(.organize, retry: { [weak self] in self?.saveOrganized(session) }) else { return }
        let document = session.document
        let pages = session.pages
        let name = String(localized: "\(document.name) (edited)")
        run(.organize, state: session.state) { _ in
            let output = OutputLocation.url(folder: "Edited", fileName: name)
            do {
                let count = try PageOrganizer.save(documentURL: document.url, pages: pages, outputURL: output)
                return ToolOutput(urls: [output], kind: .edited, pageCount: count)
            } catch {
                OutputLocation.removeFile(at: output)
                throw error
            }
        }
    }

    // MARK: - Protect & Unlock

    func protect(_ session: ProtectSession) {
        guard session.canRun else { return }
        guard mayRun(.protect, retry: { [weak self] in self?.protect(session) }) else { return }
        let document = session.document
        let mode = session.mode
        let password = session.password
        let allowPrinting = session.allowPrinting
        let allowCopying = session.allowCopying
        let permissionsPassword = document.wasLocked ? nil : session.permissionsPassword
        let name = mode == .protect
            ? String(localized: "\(document.name) (protected)")
            : String(localized: "\(document.name) (unlocked)")
        run(.protect, state: session.state) { _ in
            let output = OutputLocation.url(folder: "Protected", fileName: name)
            do {
                switch mode {
                case .protect:
                    try PDFProtector.protect(
                        documentURL: document.url, password: password,
                        allowPrinting: allowPrinting, allowCopying: allowCopying, outputURL: output
                    )
                    return ToolOutput(urls: [output], kind: .protected, pageCount: document.pageCount, detail: String(localized: "Password added"))
                case .unlock:
                    try PDFProtector.unlock(documentURL: document.url, password: permissionsPassword, outputURL: output)
                    return ToolOutput(urls: [output], kind: .protected, pageCount: document.pageCount, detail: String(localized: "Password removed"))
                }
            } catch {
                OutputLocation.removeFile(at: output)
                throw error
            }
        }
    }

    // MARK: - Compress

    func startCompressSession(with documents: [PDFDocumentInfo]) {
        guard !documents.isEmpty else { return }
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
                    session.phase = .failed(String(localized: "None of the PDFs could be compressed. They may be damaged."))
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
        guard requirePro(.tool(.merge), then: { [weak self] in self?.merge(session) }) else { return }
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
        guard requirePro(.tool(.split), then: { [weak self] in self?.split(session) }) else { return }
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

/// The PDFs the tool picker sheet is offering tools for.
struct ToolPickerContext: Identifiable {
    let id = UUID()
    let documents: [PDFDocumentInfo]

    /// Tools that fit: all PDF tools for one file, the multi-file ones for several.
    var tools: [Tool] { documents.count > 1 ? Tool.multiPDFTools : Tool.pdfTools }
}

/// A locked PDF waiting for its password.
struct PasswordRequest: Identifiable {
    let id = UUID()
    let fileName: String
    /// The previous attempt was wrong.
    let failed: Bool
}

/// Keys for values stored with @AppStorage.
nonisolated enum SettingsKeys {
    static let defaultQuality = "defaultQuality"
    static let appearance = "appearance"
    static let photoPageSize = "photoPageSize"
    static let scanFilter = "scanFilter"
}
