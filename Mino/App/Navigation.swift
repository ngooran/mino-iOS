//
//  Navigation.swift
//  Mino
//
//  Tabs, routes and presentation state shared by every layout.
//

import Foundation
import UniformTypeIdentifiers

/// The three top-level sections.
enum AppTab: String, Hashable, CaseIterable {
    case home
    case files
    case settings
}

/// Screens pushed onto a tab. On compact width they form a navigation stack;
/// on regular width the first route fills the detail column.
enum Route: Hashable {
    case compress
    case merge
    case split
    /// Every tool added after 2.0.
    case tool(Tool)
    case preview(FileItem)
    case statistics
}

/// What the file picker is choosing files for.
enum ImportTarget: Identifiable, Hashable {
    /// "Open PDF": pick a PDF, then choose a tool.
    case open
    /// The input of a tool.
    case tool(Tool)
    /// More PDFs for the open merge list.
    case mergeAdd
    /// Organize Pages: pages from another PDF.
    case insertPages

    var id: Self { self }

    var allowsMultipleSelection: Bool {
        switch self {
        case .open, .insertPages: return false
        case .mergeAdd: return true
        case .tool(let tool): return tool == .compress || tool == .merge || tool == .photosToPDF
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .tool(.photosToPDF): return ImportTypes.images
        case .tool(.officeToPDF): return ImportTypes.office
        default: return [.pdf]
        }
    }
}

/// Why the Mino Pro sheet is showing. Drives its headline.
enum PaywallReason: Identifiable, Hashable {
    case general
    case dailyLimit
    case batch
    case customQuality
    /// The final button of a Pro tool.
    case tool(Tool)
    /// Scan to PDF with "Make text searchable" switched on.
    case searchableScan

    var id: String {
        switch self {
        case .general: return "general"
        case .dailyLimit: return "dailyLimit"
        case .batch: return "batch"
        case .customQuality: return "customQuality"
        case .tool(let tool): return "tool-\(tool.rawValue)"
        case .searchableScan: return "searchableScan"
        }
    }

    var message: String {
        switch self {
        case .general:
            return String(localized: "Every PDF tool, with no limits. Pay once and keep it forever.")
        case .dailyLimit:
            return String(localized: "You've used today's \(FreeUsage.dailyLimit) free actions. Pro removes the limit.")
        case .batch:
            return String(localized: "Compressing several PDFs at once is part of Mino Pro.")
        case .customQuality:
            return String(localized: "Custom image quality and resolution are part of Mino Pro.")
        case .tool(let tool):
            return tool.paywallMessage
        case .searchableScan:
            return String(localized: "Text recognition is part of Mino Pro.")
        }
    }
}

/// App-wide links.
enum MinoLinks {
    static let appStore = URL(string: "https://apps.apple.com/app/id6757166913")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6757166913?action=write-review")!
    static let support = URL(string: "https://applestan.com/mino/support/")!
    static let privacy = URL(string: "https://applestan.com/mino/privacy/")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let sourceCode = URL(string: "https://github.com/ngooran/mino-iOS")!
    static let mupdf = URL(string: "https://mupdf.com")!
    static let agpl = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!
}
