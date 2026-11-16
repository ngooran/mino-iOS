//
//  OfficeConverter.swift
//  Mino
//
//  Office to PDF: the file is loaded into an offscreen web view, where the
//  system's own Office and iWork renderers turn it into a page, and the
//  print system paginates that into a PDF. Nothing leaves the device: the
//  web view is not allowed to load anything from the network.
//

import PDFKit
import UIKit
import WebKit

nonisolated enum OfficePageSize: String, CaseIterable, Identifiable, Sendable {
    case a4
    case letter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a4: return String(localized: "A4")
        case .letter: return String(localized: "Letter")
        }
    }

    /// Portrait size in points.
    var size: CGSize {
        switch self {
        case .a4: return CGSize(width: 595, height: 842)
        case .letter: return CGSize(width: 612, height: 792)
        }
    }

    /// The size people in this region print on.
    static var regional: OfficePageSize {
        let region = Locale.current.region?.identifier ?? ""
        return ["US", "CA", "MX", "PH", "CL", "CO", "VE"].contains(region) ? .letter : .a4
    }
}

@MainActor
final class OfficeConverter: NSObject, WKNavigationDelegate {

    enum ConvertError: LocalizedError {
        case loadFailed(String)
        case timedOut
        case empty

        var errorDescription: String? {
            switch self {
            case .loadFailed(let reason):
                return String(localized: "This file couldn't be opened: \(reason)")
            case .timedOut:
                return String(localized: "This file took too long to open.")
            case .empty:
                return String(localized: "This file has nothing to convert, or its format isn't supported.")
            }
        }
    }

    /// What a conversion found, besides the PDF it wrote.
    struct Outcome: Sendable {
        var pageCount: Int
        /// How the document was laid out on paper.
        var layout: Layout
        /// Paper size used, in points. Slides and wide sheets differ from the chosen size.
        var paper: CGSize
        /// How much the document was shrunk to fit the page width (1 = not at all).
        var scale: CGFloat
        /// The document's text, as the renderer shows it.
        var text: String
        /// Sheets in a multi-sheet workbook (0 for everything else).
        var sheetCount = 0
    }

    /// The system renders each family of documents differently, so each is
    /// put on paper in its own way.
    enum Layout: String, Sendable {
        /// Word, Pages: one flowing column with the document's own margins.
        case document
        /// PowerPoint, Keynote: one slide per page, the page as wide as the slide.
        case slides
        /// Excel, Numbers, CSV: tables at their own size; landscape and shrunk when wide.
        case sheet
        /// RTF, text, HTML: text that wraps to the page.
        case text
    }

    /// Margin around sheets and text, in points.
    static let margin: CGFloat = 36

    #if DEBUG
    /// Prints how long loading and printing took.
    static var debugTimings = false
    #endif

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// Converts a Word, Excel, PowerPoint, RTF, text, CSV or HTML file to a
    /// PDF at `outputURL`. `progress` is called with 0...1 as sheets finish.
    func convert(
        fileURL: URL,
        pageSize: OfficePageSize,
        outputURL: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws -> Outcome {
        let configuration = WKWebViewConfiguration()
        // The document must not run scripts of its own or reach the network.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        guard let rules = await Self.blockNetworkRules() else {
            // Without the block list an HTML file could load remote content.
            throw ConvertError.loadFailed(String(localized: "The offline filter couldn't be set up."))
        }
        configuration.userContentController.add(rules)
        // A workbook's sheet sits in a frame of another origin. A script that
        // runs in every frame hands the sheet's HTML over.
        let relay = SheetRelay { [weak self] html in self?.sheetHTML = html }
        configuration.userContentController.addUserScript(WKUserScript(
            source: "if (window !== window.top) { window.webkit.messageHandlers.minoSheet.postMessage(document.documentElement.outerHTML); }",
            injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient
        ))
        configuration.userContentController.add(relay, contentWorld: .defaultClient, name: "minoSheet")

        let portrait = pageSize.size
        let view = WKWebView(frame: CGRect(origin: .zero, size: portrait), configuration: configuration)
        view.navigationDelegate = self
        view.isOpaque = false
        webView = view
        // The web view lays out reliably only inside a window; keep it out of sight.
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            view.frame.origin = CGPoint(x: -portrait.width - 2000, y: 0)
            view.alpha = 0.02
            view.isUserInteractionEnabled = false
            window.addSubview(view)
        }
        defer {
            view.removeFromSuperview()
            view.navigationDelegate = nil
            webView = nil
        }

        #if DEBUG
        let started = Date()
        func mark(_ label: String) { if Self.debugTimings { print("OFFICE-TIME \(label) \(String(format: "%.2f", Date().timeIntervalSince(started)))") } }
        #else
        func mark(_ label: String) {}
        #endif

        // A workbook with several sheets becomes one copy per sheet, each
        // showing only that sheet (see WorkbookSplitter).
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("sheets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sources = await Self.sources(for: fileURL, scratch: scratch)
        mark("split into \(sources.count)")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: portrait), nil)
        var pageCount = 0
        var texts: [String] = []
        var firstPlan: Plan?
        var failure: Error?

        for (index, source) in sources.enumerated() {
            do {
                try Task.checkCancellation()
                sheetHTML = nil
                try await load(in: view) {
                    view.loadFileURL(source, allowingReadAccessTo: source.deletingLastPathComponent())
                }
                // Let layout and images settle.
                try await Task.sleep(for: .milliseconds(300))
                // A workbook is shown as a tab bar and a frame. The sheet is
                // the frame's page: load it on its own, so it can be paginated.
                if await hasSheetFrame(in: view) {
                    var waited = 0
                    while sheetHTML == nil, waited < 100 {
                        try await Task.sleep(for: .milliseconds(100))
                        waited += 1
                    }
                    if let html = sheetHTML {
                        try await load(in: view, timeout: 20) { view.loadHTMLString(Self.standalone(sheet: html), baseURL: nil) }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                }
            } catch {
                failure = error
                break
            }
            mark("loaded \(index + 1)")

            let probe = (try? await measure(view)) ?? Probe()
            let hasText = !probe.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // An empty sheet of a workbook is left out; a single document only if it has nothing at all.
            guard hasText || probe.images > 0 || (sources.count == 1 && probe.elements > 1) else { continue }
            let plan = Self.plan(for: probe, portrait: portrait)
            if firstPlan == nil { firstPlan = plan }
            texts.append(probe.text)

            // WebKit lays a page out a quarter wider than the paper and prints
            // it at 80%. Zooming by the same quarter gives true size.
            var script = "var s = document.createElement('style'); s.textContent = \"\(plan.css)\"; document.head.appendChild(s);"
            script += " document.documentElement.style.zoom = '\(plan.scale * Self.printShrinkCompensation)';"
            _ = try? await view.evaluateJavaScript(script + " 0")
            try? await Task.sleep(for: .milliseconds(120))

            let paperRect = CGRect(origin: .zero, size: plan.paper)
            let renderer = PageRenderer(paper: paperRect, printable: paperRect.inset(by: plan.insets))
            renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
            var pages = renderer.numberOfPages
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
            if plan.layout == .sheet || plan.layout == .text, pages > 1 {
                // Sheets often end in formatted but empty rows: don't print pages of nothing.
                pages -= Self.trailingBlankPages(of: renderer, pages: pages, paper: paperRect)
            }
            for page in 0..<pages {
                UIGraphicsBeginPDFPageWithInfo(paperRect, nil)
                renderer.drawPage(at: page, in: paperRect)
            }
            pageCount += pages
            progress?(Double(index + 1) / Double(sources.count))
        }
        UIGraphicsEndPDFContext()
        mark("printed \(pageCount) pages")

        if let failure { throw failure }
        guard pageCount > 0, data.length > 0, let plan = firstPlan else { throw ConvertError.empty }

        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)
        try (data as Data).write(to: outputURL, options: .atomic)

        let outcome = Outcome(
            pageCount: pageCount, layout: plan.layout, paper: plan.paper, scale: plan.scale,
            text: texts.joined(separator: "\n\n"), sheetCount: sources.count > 1 ? sources.count : 0
        )
        return outcome
    }

    /// The files to load: the document itself, or one copy per visible sheet
    /// of an Excel workbook that has several.
    private static func sources(for fileURL: URL, scratch: URL) async -> [URL] {
        guard ["xls", "xlsx", "xlsm", "xlt", "xltx"].contains(fileURL.pathExtension.lowercased()) else { return [fileURL] }
        return await Task.detached(priority: .userInitiated) {
            guard let sheets = WorkbookSplitter.visibleSheets(in: fileURL), sheets.count > 1 else { return [fileURL] }
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            var copies: [URL] = []
            for sheet in sheets {
                let copy = scratch.appendingPathComponent("sheet-\(sheet).\(fileURL.pathExtension)")
                do {
                    try WorkbookSplitter.writeCopy(of: fileURL, showingOnly: sheet, to: copy)
                    copies.append(copy)
                } catch {
                    // Leave the workbook as it is; the first sheet is still converted.
                    return [fileURL]
                }
            }
            return copies
        }.value
    }

    // MARK: - Layout

    private struct Plan {
        var layout: Layout
        var paper: CGSize
        var insets: UIEdgeInsets
        var scale: CGFloat
        var css: String
    }

    /// Decides the paper, the margins and the scale for what was measured.
    private static func plan(for probe: Probe, portrait: CGSize) -> Plan {
        let margins = UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
        // Print fills and colors as they are shown. By default WebKit leaves
        // backgrounds out and darkens light text, as for an ink-saving printout.
        let colors = "* { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; } "
        let reset = colors + "html, body { margin: 0 !important; padding: 0 !important; } "

        if probe.slideCount > 0, probe.slideWidth > 0, probe.slideHeight > 0 {
            // One slide per page; the page takes the slide's shape.
            let width = max(portrait.width, portrait.height)
            let scale = width / probe.slideWidth
            return Plan(
                layout: .slides,
                // A point taller than the slide, so rounding never pushes a sliver onto a second page.
                paper: CGSize(width: width, height: (probe.slideHeight * scale).rounded(.up) + 1),
                insets: .zero,
                scale: scale,
                css: reset + "div.slide { margin: 0 !important; page-break-after: always; page-break-inside: avoid; }"
            )
        }
        if probe.pageWidth > 0 {
            // The renderer drew one long page, with the document's margins as
            // padding. Side margins stay as drawn (things may reach into them);
            // the top and bottom margins become the paper's, so they are kept
            // on every sheet of paper.
            let scale = portrait.width / probe.pageWidth
            let top = max(18, (probe.pagePaddingY * scale).rounded())
            return Plan(
                layout: .document,
                paper: portrait,
                insets: UIEdgeInsets(top: top, left: 0, bottom: top, right: 0),
                scale: scale,
                css: reset + "body > div { padding-top: 0 !important; padding-bottom: 0 !important; min-height: 0 !important; }"
            )
        }
        if probe.tableOnly {
            var paper = portrait
            var scale: CGFloat = 1
            if probe.contentWidth > portrait.width - margin * 2 {
                // Wide sheets go on landscape paper, shrunk if they still don't fit.
                paper = CGSize(width: portrait.height, height: portrait.width)
                scale = max(minimumSheetScale, min(1, (paper.width - margin * 2) / probe.contentWidth))
            }
            return Plan(
                layout: .sheet, paper: paper, insets: margins, scale: scale,
                css: reset + "html, body, body > div { height: auto !important; min-height: 0 !important; } tr { page-break-inside: avoid; }"
            )
        }
        return Plan(layout: .text, paper: portrait, insets: margins, scale: 1, css: colors + "html, body { margin: 0 !important; } img, table { max-width: 100% !important; }")
    }

    /// How many pages at the end have no text and nothing drawn darker than a grid line.
    private static func trailingBlankPages(of renderer: UIPrintPageRenderer, pages: Int, paper: CGRect) -> Int {
        // Draw the pages once into a scratch PDF to look at them.
        let scratch = NSMutableData()
        UIGraphicsBeginPDFContextToData(scratch, paper, nil)
        for page in 0..<pages {
            UIGraphicsBeginPDFPageWithInfo(paper, nil)
            renderer.drawPage(at: page, in: paper)
        }
        UIGraphicsEndPDFContext()
        guard let document = PDFDocument(data: scratch as Data) else { return 0 }

        var blank = 0
        // The first page always stays.
        for index in stride(from: document.pageCount - 1, to: 0, by: -1) {
            guard let page = document.page(at: index), isBlank(page) else { break }
            blank += 1
        }
        return blank
    }

    private static func isBlank(_ page: PDFPage) -> Bool {
        if !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        let bounds = page.bounds(for: .mediaBox)
        let width = 120
        let height = max(1, Int(CGFloat(width) * bounds.height / max(1, bounds.width)))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return false }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        page.draw(with: .mediaBox, to: context)
        // Grid lines are light gray; anything darker counts as content.
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] < 170 || pixels[index + 1] < 170 || pixels[index + 2] < 170 {
            return false
        }
        return true
    }

    /// See the comment where the zoom is set.
    static let printShrinkCompensation: CGFloat = 1.25

    /// A very wide sheet is not shrunk below this; it is cut off on the right instead of becoming unreadable.
    static let minimumSheetScale: CGFloat = 0.35

    /// The HTML of the sheet in a workbook's frame, once its script has reported it.
    private var sheetHTML: String?

    private func hasSheetFrame(in view: WKWebView) async -> Bool {
        ((try? await view.evaluateJavaScript("document.getElementById('SheetFrame') ? 1 : 0") as? Int) ?? 0) == 1
    }

    /// Makes a sheet's HTML loadable on its own. Its style sheets belong to
    /// the preview and can't be loaded from here, so the few rules a sheet
    /// needs (grid lines; cells that don't wrap and, as in Excel, spill over
    /// empty neighbors) are supplied instead.
    static func standalone(sheet html: String) -> String {
        var page = html
        if let links = try? NSRegularExpression(pattern: "<link[^>]*>", options: .caseInsensitive) {
            page = links.stringByReplacingMatches(in: page, range: NSRange(page.startIndex..., in: page), withTemplate: "")
        }
        let style = """
        <style>
        body { margin: 0; font-family: Helvetica, Arial, sans-serif; font-size: 11px; }
        table.worksheet { border-collapse: collapse; table-layout: fixed; }
        table.worksheet td { white-space: nowrap; overflow: visible; vertical-align: bottom; padding: 0 2px; }
        table.showGridlines td { border: 1px solid #D0D0D0; }
        </style>
        """
        if let head = page.range(of: "<head>", options: .caseInsensitive) {
            // First in the head, so the sheet's own rules win.
            page.insert(contentsOf: style, at: head.upperBound)
        } else {
            page = style + page
        }
        return page
    }

    // MARK: - Measuring

    private struct Probe {
        var text = ""
        var elements = 0
        var images = 0
        var slideCount = 0
        var slideWidth: CGFloat = 0
        var slideHeight: CGFloat = 0
        /// The body holds tables and nothing else worth mentioning.
        var tableOnly = false
        /// Right edge of the widest table or other content, in CSS pixels.
        var contentWidth: CGFloat = 0
        /// Word-like documents: width of the page the renderer drew, and its padding.
        var pageWidth: CGFloat = 0
        var pagePaddingX: CGFloat = 0
        var pagePaddingY: CGFloat = 0
    }

    /// Asks the page what the renderer made of the file.
    private func measure(_ view: WKWebView) async throws -> Probe {
        let script = """
        (function () {
            var body = document.body;
            if (!body) { return JSON.stringify({}); }
            var result = { text: body.innerText || '', elements: body.querySelectorAll('*').length, images: document.images.length };
            var slides = document.querySelectorAll('div.slide');
            if (slides.length) {
                var r = slides[0].getBoundingClientRect();
                result.slideCount = slides.length; result.slideWidth = r.width; result.slideHeight = r.height;
                return JSON.stringify(result);
            }
            var page = body.querySelector(':scope > div');
            var viewport = document.querySelector('meta[name=viewport]');
            var isDocument = page && viewport && /width=\\d+/.test(viewport.getAttribute('content') || '') && !slides.length;
            if (isDocument) {
                var style = getComputedStyle(page);
                result.pageWidth = page.getBoundingClientRect().width;
                result.pagePaddingX = parseFloat(style.paddingLeft) || 0;
                result.pagePaddingY = parseFloat(style.paddingTop) || 0;
                return JSON.stringify(result);
            }
            // Drawings and text boxes in sheets sometimes come with their place
            // and size in EMU (12700 to a point) written as pixels, which puts
            // them millions of pixels away. Bring those back to points.
            var placed = body.querySelectorAll('img, div');
            for (var p = 0; p < Math.min(placed.length, 5000); p++) {
                var cs = getComputedStyle(placed[p]);
                if (cs.position !== 'absolute') { continue; }
                var keys = ['top', 'left', 'width', 'height'];
                var values = keys.map(function (k) { return parseFloat(cs[k]) || 0; });
                if (!values.some(function (v) { return v > 200000; })) { continue; }
                for (var k = 0; k < keys.length; k++) {
                    placed[p].style.setProperty(keys[k], (values[k] / 12700) + 'px', 'important');
                }
            }
            var tables = document.querySelectorAll('table');
            var tableText = 0;
            var width = 0;
            for (var i = 0; i < tables.length; i++) {
                var table = tables[i];
                // Sheets are often formatted far below their last entry: drop the empty rows at the end.
                for (var r = table.rows.length - 1; r >= 0; r--) {
                    var row = table.rows[r];
                    if ((row.textContent || '').trim() === '' && !row.querySelector('img')) { row.parentNode.removeChild(row); } else { break; }
                }
                tableText += (table.textContent || '').length;
                // The used width: the right edge of the last cell that holds something.
                var cells = table.querySelectorAll('td, th');
                var limit = Math.min(cells.length, 20000);
                var used = 0;
                for (var c = 0; c < limit; c++) {
                    if ((cells[c].textContent || '').trim() !== '' || cells[c].querySelector('img')) {
                        used = Math.max(used, cells[c].getBoundingClientRect().right);
                    }
                }
                width = Math.max(width, used > 0 && cells.length <= 20000 ? used : table.getBoundingClientRect().right);
            }
            result.text = body.innerText || '';
            result.contentWidth = width;
            result.tableOnly = tables.length > 0 && tableText >= ((body.textContent || '').length * 0.9);
            return JSON.stringify(result);
        })()
        """
        guard let json = try await view.evaluateJavaScript(script) as? String,
              let values = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return Probe()
        }
        func number(_ key: String) -> CGFloat { CGFloat((values[key] as? NSNumber)?.doubleValue ?? 0) }
        return Probe(
            text: values["text"] as? String ?? "",
            elements: (values["elements"] as? NSNumber)?.intValue ?? 0,
            images: (values["images"] as? NSNumber)?.intValue ?? 0,
            slideCount: (values["slideCount"] as? NSNumber)?.intValue ?? 0,
            slideWidth: number("slideWidth"),
            slideHeight: number("slideHeight"),
            tableOnly: (values["tableOnly"] as? NSNumber)?.boolValue ?? false,
            contentWidth: number("contentWidth"),
            pageWidth: number("pageWidth"),
            pagePaddingX: number("pagePaddingX"),
            pagePaddingY: number("pagePaddingY")
        )
    }

    // MARK: - Loading

    /// The navigation `load` is waiting for. Callbacks for others are ignored:
    /// starting a load cancels whatever was still in flight, and that
    /// cancellation must not be mistaken for a failure of the new load.
    private var awaitedNavigation: WKNavigation?

    private func load(in view: WKWebView, timeout seconds: Double = 45, _ start: () -> WKNavigation?) async throws {
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishLoading(.failure(ConvertError.timedOut))
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            awaitedNavigation = start()
        }
    }

    private func finishLoading(_ result: Result<Void, Error>) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        awaitedNavigation = nil
        continuation.resume(with: result)
    }

    private func isAwaited(_ navigation: WKNavigation?) -> Bool {
        awaitedNavigation == nil || navigation === awaitedNavigation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isAwaited(navigation) else { return }
        finishLoading(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isAwaited(navigation) else { return }
        finishLoading(.failure(ConvertError.loadFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isAwaited(navigation) else { return }
        finishLoading(.failure(ConvertError.loadFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Only the file itself (and what the renderer makes of it) may load.
        guard let url = navigationAction.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""
        return ["file", "about", "data", "blob", "x-apple-ql-id", "x-apple-ql-id2", "applewebdata"].contains(scheme) ? .allow : .cancel
    }

    // MARK: - No network

    private static var cachedRules: WKContentRuleList?

    /// A content rule list that blocks every http, https and websocket load.
    private static func blockNetworkRules() async -> WKContentRuleList? {
        if let cachedRules { return cachedRules }
        let json = #"""
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]
        """#
        let rules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "mino-offline", encodedContentRuleList: json)
        cachedRules = rules
        return rules
    }
}

/// A print renderer for a fixed paper size. The paper and printable
/// rectangles are read-only in UIKit; a subclass may supply them.
private final class PageRenderer: UIPrintPageRenderer {
    private let paper: CGRect
    private let printable: CGRect

    init(paper: CGRect, printable: CGRect) {
        self.paper = paper
        self.printable = printable
        super.init()
    }

    override var paperRect: CGRect { paper }
    override var printableRect: CGRect { printable }
}

/// Receives the HTML a sheet's frame reports. The user content controller
/// keeps its handlers alive, so this small object stands in for the converter.
private final class SheetRelay: NSObject, WKScriptMessageHandler {
    private let onSheet: (String) -> Void

    init(onSheet: @escaping (String) -> Void) {
        self.onSheet = onSheet
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !message.frameInfo.isMainFrame, let html = message.body as? String else { return }
        onSheet(html)
    }
}
