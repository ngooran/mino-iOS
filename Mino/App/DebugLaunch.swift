//
//  DebugLaunch.swift
//  Mino
//
//  DEBUG only: open a screen with sample PDFs from launch arguments, for
//  screenshots and layout checks on every device.
//
//  xcrun simctl launch booted com.applestan.Mino -demoScreen compress -demoFree
//  Screens: home, compress, result, merge, split, files, settings, paywall
//

#if DEBUG
import SwiftUI
import UIKit

@MainActor
enum DebugLaunch {

    static func apply(to appState: AppState) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoScreen"), index + 1 < arguments.count else { return }
        let screen = arguments[index + 1]

        if arguments.contains("-demoPro") { appState.store.debugProOverride = true }
        if arguments.contains("-demoFree") { appState.store.debugProOverride = false; appState.usage.reset() }

        let lease = makeSamplePDF(name: "Lease Agreement", pages: 12, photos: true)
        let receipts = makeSamplePDF(name: "Scanned Receipts", pages: 8, photos: true)
        let tax = makeSamplePDF(name: "Tax Return 2025", pages: 6, photos: false)

        if StorageRoot.isDemoSandbox {
            if let appearance = value(after: "-demoAppearance", in: arguments) {
                StorageRoot.defaults.set(appearance, forKey: SettingsKeys.appearance)
            }
            await seedScreenshotLibrary(appState: appState, lease: lease, receipts: receipts, tax: tax)
        } else if appState.files.isEmpty, let seed = try? await appState.documentImporter.importDocument(from: receipts) {
            // Seed one finished file so Home and Files have content.
            _ = try? await appState.compressionService.compress(document: seed, settings: CompressionQuality.medium.settings)
        }

        switch screen {
        case "compress":
            await appState.receive([lease])
        case "result":
            await appState.receive([lease])
            if let session = appState.compressSession { appState.compress(session) }
        case "merge":
            let wasPro = appState.store.debugProOverride
            appState.store.debugProOverride = true
            appState.mergeSession = MergeSession()
            appState.show(.merge)
            await appState.receive([lease, receipts, tax])
            if arguments.contains("-demoRun"), let session = appState.mergeSession {
                appState.store.debugProOverride = true
                appState.merge(session)
                return
            }
            appState.store.debugProOverride = wasPro
        case "split":
            let wasPro = appState.store.debugProOverride
            appState.store.debugProOverride = true
            if let document = try? await appState.documentImporter.importDocument(from: lease) {
                let session = SplitSession(document: document)
                session.selectedPages = [1, 2, 3, 7]
                appState.splitSession = session
                appState.show(.split)
                if arguments.contains("-demoRun") {
                    appState.split(session)
                    return
                }
            }
            appState.store.debugProOverride = wasPro
        case "files":
            appState.selectedTab = .files
        case "settings":
            appState.selectedTab = .settings
        case "paywall":
            appState.showPaywall(.merge)
        default:
            break
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// A believable library for App Store screenshots: compressed, merged and split files.
    private static func seedScreenshotLibrary(appState: AppState, lease: URL, receipts: URL, tax: URL) async {
        let photos = makeSamplePDF(name: "Holiday Photos", pages: 10, photos: true)
        let invoice = makeSamplePDF(name: "Invoice March", pages: 2, photos: false)
        let contract = makeSamplePDF(name: "Rental Contract", pages: 9, photos: true)
        let importer = appState.documentImporter

        // Oldest first, so the list reads newest at the top.
        if let doc = try? await importer.importDocument(from: contract) {
            _ = try? await appState.splitService.extractPages(from: doc, pages: [1, 2, 3])
        }
        if let a = try? await importer.importDocument(from: tax),
           let b = try? await importer.importDocument(from: invoice) {
            _ = try? await appState.mergeService.merge(
                documents: [a, b],
                outputName: PDFMerger.suggestedOutputName(from: [a, b])
            )
        }
        for source in [photos, receipts] {
            if let doc = try? await importer.importDocument(from: source) {
                _ = try? await appState.compressionService.compress(document: doc, settings: CompressionQuality.medium.settings)
            }
        }
    }

    /// Draws a sample PDF with text and (optionally) large photo-like images.
    private static func makeSamplePDF(name: String, pages: Int, photos: Bool) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let photo = photos ? makePhoto(size: CGSize(width: 1800, height: 1200)) : nil
        let data = renderer.pdfData { context in
            for page in 1...pages {
                context.beginPage()
                let title = "\(name) — page \(page)" as NSString
                title.draw(at: CGPoint(x: 54, y: 54), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22)])
                if let photo, page % 2 == 1 {
                    photo.draw(in: CGRect(x: 54, y: 100, width: 504, height: 336))
                }
                let body = String(repeating: "This agreement is made between the parties named above. ", count: 30) as NSString
                body.draw(in: CGRect(x: 54, y: photo != nil && page % 2 == 1 ? 460 : 100, width: 504, height: 300),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
        try? data.write(to: url)
        return url
    }

    private static func makePhoto(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 0.5, green: 0.7, blue: 0.8, alpha: 1).cgColor,
                          UIColor(red: 0.24, green: 0.43, blue: 0.53, alpha: 1).cgColor,
                          UIColor(red: 0.79, green: 0.64, blue: 0.42, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.6, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            // Noise so the image behaves like a real photo when compressed.
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<60_000 {
                let x = CGFloat.random(in: 0..<size.width, using: &generator)
                let y = CGFloat.random(in: 0..<size.height, using: &generator)
                UIColor(white: .random(in: 0...1, using: &generator), alpha: 0.35).setFill()
                context.fill(CGRect(x: x, y: y, width: 3, height: 3))
            }
        }
    }
}
#endif
