//
//  Navigation.swift
//  Mino
//
//  Tabs, routes and presentation state shared by every layout.
//

import Foundation

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
    case preview(FileItem)
    case statistics
}

/// What the file picker is choosing PDFs for.
enum ImportTarget: Identifiable {
    case compress
    case merge
    case split

    var id: Self { self }

    var allowsMultipleSelection: Bool {
        self != .split
    }
}

/// Why the Mino Pro sheet is showing. Drives its headline.
enum PaywallReason: String, Identifiable {
    case general
    case dailyLimit
    case batch
    case merge
    case split
    case customQuality

    var id: String { rawValue }

    var message: String {
        switch self {
        case .general:
            return "Every PDF tool, with no limits. Pay once and keep it forever."
        case .dailyLimit:
            return "You've used today's \(FreeUsage.dailyLimit) free compressions. Pro removes the limit."
        case .batch:
            return "Compressing several PDFs at once is part of Mino Pro."
        case .merge:
            return "Merging PDFs is part of Mino Pro."
        case .split:
            return "Splitting PDFs is part of Mino Pro."
        case .customQuality:
            return "Custom image quality and resolution are part of Mino Pro."
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
