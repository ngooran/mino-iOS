//
//  ToolResult.swift
//  Mino
//
//  What a tool produced. Tools added after 2.0 share this model and one
//  store, instead of a result type and a history each.
//

import Foundation

/// The files a tool engine wrote, before they are added to the library.
nonisolated struct ToolOutput: Sendable {
    /// One file for most tools; one per page for PDF to Images.
    var urls: [URL]
    var kind: FileItem.Kind
    /// Pages in the PDF, or the number of images.
    var pageCount: Int?
    /// Short outcome shown under the name, e.g. "12 JPG images" or "Searchable".
    var detail: String?
    /// Text the tool recognized or extracted, shown on the result screen.
    var text: String?

    init(urls: [URL], kind: FileItem.Kind, pageCount: Int? = nil, detail: String? = nil, text: String? = nil) {
        self.urls = urls
        self.kind = kind
        self.pageCount = pageCount
        self.detail = detail
        self.text = text
    }

    var totalSize: Int64 {
        urls.reduce(0) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return total + (size ?? 0)
        }
    }
}

/// A stored result of a tool.
nonisolated struct ToolResult: Identifiable, Sendable {
    let id: UUID
    let tool: Tool
    let kind: FileItem.Kind
    let urls: [URL]
    let size: Int64
    let date: Date
    let pageCount: Int?
    let detail: String?

    init(id: UUID = UUID(), tool: Tool, output: ToolOutput, date: Date = Date()) {
        self.id = id
        self.tool = tool
        self.kind = output.kind
        self.urls = output.urls
        self.size = output.totalSize
        self.date = date
        self.pageCount = output.pageCount
        self.detail = output.detail
    }

    fileprivate init(id: UUID, tool: Tool, kind: FileItem.Kind, urls: [URL], size: Int64, date: Date, pageCount: Int?, detail: String?) {
        self.id = id
        self.tool = tool
        self.kind = kind
        self.urls = urls
        self.size = size
        self.date = date
        self.pageCount = pageCount
        self.detail = detail
    }
}

/// How a result is saved: paths relative to Documents, so they survive the
/// app container moving.
nonisolated struct StoredToolResult: Codable, Sendable {
    let id: UUID
    let tool: String
    let kind: String
    let relativePaths: [String]
    let size: Int64
    let date: Date
    let pageCount: Int?
    let detail: String?

    init(_ result: ToolResult) {
        id = result.id
        tool = result.tool.rawValue
        kind = result.kind.rawValue
        relativePaths = result.urls.map(OutputLocation.relativePath(of:))
        size = result.size
        date = result.date
        pageCount = result.pageCount
        detail = result.detail
    }

    /// Nil when the files are gone or the record is from an unknown tool.
    var result: ToolResult? {
        guard let tool = Tool(rawValue: tool), let kind = FileItem.Kind(rawValue: kind) else { return nil }
        let urls = relativePaths
            .map(OutputLocation.resolve(relativePath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return nil }
        return ToolResult(id: id, tool: tool, kind: kind, urls: urls, size: size, date: date, pageCount: pageCount, detail: detail)
    }
}
