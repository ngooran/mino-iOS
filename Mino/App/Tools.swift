//
//  Tools.swift
//  Mino
//
//  The tool registry: every tool Mino offers, in one place. Home, search,
//  the "What do you want to do?" sheet, the paywall and incoming files all
//  read from here.
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated enum Tool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case scan
    case photosToPDF
    case compress
    case merge
    case split
    case organize
    case fillSign
    case edit
    case pdfToImages
    case officeToPDF
    case pdfToWord
    case ocr
    case protect

    var id: String { rawValue }

    // MARK: - Grouping

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case create
        case organize
        case signEdit
        case convert
        case protect

        var id: String { rawValue }

        var title: String {
            switch self {
            case .create: return String(localized: "Create")
            case .organize: return String(localized: "Reduce & Organize")
            case .signEdit: return String(localized: "Sign & Edit")
            case .convert: return String(localized: "Convert")
            case .protect: return String(localized: "Protect")
            }
        }

        /// Tools of this category that ship in this build, in display order.
        var tools: [Tool] { Tool.available.filter { $0.category == self } }
    }

    /// Who can run the tool.
    enum Access: Sendable {
        /// Free, counted against the shared daily allowance.
        case freeAllowance
        /// Opens for everyone; the final button needs Mino Pro.
        case pro
    }

    /// What the tool starts from.
    enum Input: Sendable {
        case pdf
        case images
        case camera
        case office
    }

    // MARK: - Availability

    /// Tools that ship in this build, in Home order. A tool is added here when
    /// its release is finished (see ROADMAP.md, "Progress").
    static let available: [Tool] = [
        .scan, .photosToPDF,
        .compress, .merge, .split, .organize,
        .pdfToImages,
        .protect,
    ]

    var isAvailable: Bool { Tool.available.contains(self) }

    /// The release that introduced the tool.
    var release: String {
        switch self {
        case .compress, .merge, .split: return "2.0"
        case .photosToPDF, .pdfToImages, .organize, .protect: return "2.1"
        case .scan, .ocr: return "2.2"
        case .fillSign, .edit: return "2.3"
        case .officeToPDF, .pdfToWord: return "2.4"
        }
    }

    /// Tools from the newest release get a "NEW" badge on Home.
    var isNew: Bool {
        let newest = Tool.available.map(\.release).max() ?? "2.0"
        return newest != "2.0" && release == newest
    }

    /// Tools offered for an open PDF, in the order of the tool picker sheet.
    static var pdfTools: [Tool] {
        [.compress, .fillSign, .edit, .organize, .pdfToImages, .pdfToWord, .ocr, .protect, .split, .merge]
            .filter(\.isAvailable)
    }

    /// Tools that can take several PDFs at once.
    static var multiPDFTools: [Tool] { [.compress, .merge].filter(\.isAvailable) }

    // MARK: - Description

    var title: String {
        switch self {
        case .scan: return String(localized: "Scan to PDF")
        case .photosToPDF: return String(localized: "Photos to PDF")
        case .compress: return String(localized: "Compress")
        case .merge: return String(localized: "Merge")
        case .split: return String(localized: "Split")
        case .organize: return String(localized: "Organize Pages")
        case .fillSign: return String(localized: "Fill & Sign")
        case .edit: return String(localized: "Edit & Annotate")
        case .pdfToImages: return String(localized: "PDF to Images")
        case .officeToPDF: return String(localized: "Office to PDF")
        case .pdfToWord: return String(localized: "PDF to Word")
        case .ocr: return String(localized: "Recognize Text")
        case .protect: return String(localized: "Protect & Unlock")
        }
    }

    var subtitle: String {
        switch self {
        case .scan: return String(localized: "Camera, auto-crop, multi-page")
        case .photosToPDF: return String(localized: "JPG, PNG, HEIC into one PDF")
        case .compress: return String(localized: "Make big files small")
        case .merge: return String(localized: "Combine PDFs into one")
        case .split: return String(localized: "Extract or separate pages")
        case .organize: return String(localized: "Rotate, delete, reorder")
        case .fillSign: return String(localized: "Forms, signature, date")
        case .edit: return String(localized: "Text, highlight, draw")
        case .pdfToImages: return String(localized: "Pages as JPG or PNG")
        case .officeToPDF: return String(localized: "Word, Excel, PowerPoint")
        case .pdfToWord: return String(localized: "Editable .docx or text")
        case .ocr: return String(localized: "Searchable PDF, copy text")
        case .protect: return String(localized: "Add or remove a password")
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "doc.viewfinder"
        case .photosToPDF: return "photo.on.rectangle"
        case .compress: return "arrow.down.doc.fill"
        case .merge: return "doc.on.doc.fill"
        case .split: return "scissors"
        case .organize: return "square.grid.2x2.fill"
        case .fillSign: return "signature"
        case .edit: return "pencil.tip"
        case .pdfToImages: return "photo.stack"
        case .officeToPDF: return "doc.richtext.fill"
        case .pdfToWord: return "doc.text.fill"
        case .ocr: return "text.viewfinder"
        case .protect: return "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .scan: return .teal
        case .photosToPDF: return .green
        case .compress: return .teal
        case .merge: return .indigo
        case .split: return .orange
        case .organize: return .purple
        case .fillSign: return .pink
        case .edit: return .yellow
        case .pdfToImages: return .cyan
        case .officeToPDF: return .blue
        case .pdfToWord: return .blue
        case .ocr: return .mint
        case .protect: return .gray
        }
    }

    var category: Category {
        switch self {
        case .scan, .photosToPDF: return .create
        case .compress, .merge, .split, .organize: return .organize
        case .fillSign, .edit: return .signEdit
        case .pdfToImages, .officeToPDF, .pdfToWord, .ocr: return .convert
        case .protect: return .protect
        }
    }

    var access: Access {
        switch self {
        case .compress, .scan, .photosToPDF, .pdfToImages, .organize:
            return .freeAllowance
        case .merge, .split, .fillSign, .edit, .protect, .ocr, .officeToPDF, .pdfToWord:
            return .pro
        }
    }

    var input: Input {
        switch self {
        case .scan: return .camera
        case .photosToPDF: return .images
        case .officeToPDF: return .office
        default: return .pdf
        }
    }

    /// Extra words the Home search matches, besides the title and subtitle.
    var keywords: String {
        switch self {
        case .scan: return "camera scanner document paper receipt"
        case .photosToPDF: return "jpg jpeg png heic image picture photo convert"
        case .compress: return "shrink reduce size smaller email"
        case .merge: return "combine join"
        case .split: return "extract separate pages"
        case .organize: return "rotate delete remove reorder rearrange move duplicate insert pages"
        case .fillSign: return "signature form fill contract initials date checkbox"
        case .edit: return "editor markup highlight draw note text white-out annotate comment"
        case .pdfToImages: return "jpg jpeg png picture photo export convert"
        case .officeToPDF: return "word docx excel xlsx powerpoint pptx pages numbers keynote convert"
        case .pdfToWord: return "docx doc text txt editable convert"
        case .ocr: return "ocr searchable text copy extract scan recognize"
        case .protect: return "password lock encrypt secure unlock remove"
        }
    }

    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        let haystack = "\(title) \(subtitle) \(keywords)".lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The screen that runs the tool.
    var route: Route {
        switch self {
        case .compress: return .compress
        case .merge: return .merge
        case .split: return .split
        default: return .tool(self)
        }
    }

    /// Why the paywall shows when a free customer taps the tool's final button.
    var paywallMessage: String {
        switch self {
        case .merge: return String(localized: "Merging PDFs is part of Mino Pro.")
        case .split: return String(localized: "Splitting PDFs is part of Mino Pro.")
        case .fillSign: return String(localized: "Signing PDFs is part of Mino Pro.")
        case .edit: return String(localized: "Editing PDFs is part of Mino Pro.")
        case .protect: return String(localized: "Password protection is part of Mino Pro.")
        case .ocr: return String(localized: "Text recognition is part of Mino Pro.")
        case .officeToPDF: return String(localized: "Converting Office files is part of Mino Pro.")
        case .pdfToWord: return String(localized: "Converting to Word is part of Mino Pro.")
        case .compress, .scan, .photosToPDF, .pdfToImages, .organize:
            return String(localized: "Every PDF tool, with no limits. Pay once and keep it forever.")
        }
    }
}

// MARK: - File types

nonisolated enum ImportTypes {
    /// Images that Photos to PDF accepts.
    static let images: [UTType] = [.image]

    /// Documents that Office to PDF accepts.
    static let office: [UTType] = {
        var types: [UTType] = [.rtf, .rtfd, .plainText, .html]
        let identifiers = [
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.word.doc",
            "org.openxmlformats.spreadsheetml.sheet",
            "com.microsoft.excel.xls",
            "org.openxmlformats.presentationml.presentation",
            "com.microsoft.powerpoint.ppt",
            "com.apple.iwork.pages.sffpages",
            "com.apple.iwork.pages.pages",
            "com.apple.iwork.numbers.sffnumbers",
            "com.apple.iwork.numbers.numbers",
            "com.apple.iwork.keynote.sffkey",
            "com.apple.iwork.keynote.key",
            "public.comma-separated-values-text",
        ]
        types.append(contentsOf: identifiers.compactMap { UTType($0) })
        return types
    }()

    static let officeExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "rtfd", "txt", "csv", "html", "htm",
    ]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
    ]

    enum FileClass { case pdf, image, office, other }

    static func classify(_ url: URL) -> FileClass {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        if officeExtensions.contains(ext) { return .office }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
        }
        return .other
    }
}
