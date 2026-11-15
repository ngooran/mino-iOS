//
//  DebugLaunch.swift
//  Mino
//
//  DEBUG only: open a screen with sample PDFs from launch arguments, for
//  screenshots and layout checks on every device.
//
//  xcrun simctl launch booted com.applestan.Mino -demoScreen compress -demoFree
//  Screens: home, search, picker, password, compress, result, merge, split,
//  scan, photos, images, organize, protect, unlock, files, settings, paywall
//  Add -demoRun to run the tool and show its result.
//

#if DEBUG
import CoreImage
import CoreImage.CIFilterBuiltins
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

        let run = arguments.contains("-demoRun")

        switch screen {
        case "search":
            appState.toolQuery = value(after: "-demoQuery", in: arguments) ?? "jpg"
        case "picker":
            let documents = await appState.importDocuments([lease])
            appState.showToolPicker(for: documents)
        case "password":
            // Shows the password prompt. The sample's password is "mino".
            await appState.receive([makeLockedPDF()])
        case "compress":
            appState.start(.compress, with: await appState.importDocuments([lease]))
        case "result":
            appState.start(.compress, with: await appState.importDocuments([lease]))
            if let session = appState.compressSession { appState.compress(session) }
        case "merge":
            appState.mergeSession = MergeSession()
            appState.start(.merge, with: await appState.importDocuments([lease, receipts, tax]))
            if run, let session = appState.mergeSession {
                appState.store.debugProOverride = true
                appState.merge(session)
            }
        case "split":
            appState.start(.split, with: await appState.importDocuments([lease]))
            if let session = appState.splitSession {
                session.selectedPages = [1, 2, 3, 7]
                if run {
                    appState.store.debugProOverride = true
                    appState.split(session)
                }
            }
        case "scan":
            // The document camera can't run in the simulator: sample pages stand in.
            appState.openScan()
            if !arguments.contains("-demoEmpty") {
                appState.addScanFiles(makeSampleScanPages(count: Int(value(after: "-demoPages", in: arguments) ?? "") ?? 4))
            }
            if let session = appState.scanSession {
                if let filter = value(after: "-demoFilter", in: arguments).flatMap(ScanFilter.init(rawValue:)) {
                    session.filter = filter
                }
                if arguments.contains("-demoSearchable") { session.makeSearchable = true }
                if run {
                    if session.makeSearchable { appState.store.debugProOverride = true }
                    appState.saveScan(session)
                }
            }
        case "photos":
            appState.openPhotosToPDF()
            await appState.addPhotos(from: makeSamplePhotos())
            if let session = appState.photosSession {
                if let size = value(after: "-demoPageSize", in: arguments).flatMap(PhotoPageSize.init(rawValue:)) {
                    session.pageSize = size
                }
                if run { appState.createPDF(session) }
            }
        case "images":
            appState.start(.pdfToImages, with: await appState.importDocuments([lease]))
            if let session = appState.imagesSession {
                if arguments.contains("-demoChoose") {
                    session.scope = .choose
                    session.selectedPages = [1, 2, 5]
                }
                if arguments.contains("-demoPNG") { session.format = .png }
                if run { appState.exportImages(session) }
            }
        case "organize":
            appState.start(.organize, with: await appState.importDocuments([lease]))
            if let session = appState.organizeSession {
                // Page 2 turned, page 5 removed, pages 3 and 4 selected.
                session.selection = [session.pages[1].id]
                session.rotateSelection()
                session.selection = [session.pages[4].id]
                session.deleteSelection()
                session.selection = [session.pages[2].id, session.pages[3].id]
                if run { appState.saveOrganized(session) }
            }
        case "protect":
            appState.start(.protect, with: await appState.importDocuments([lease]))
            if let session = appState.protectSession {
                session.password = "mino-demo"
                session.confirmation = "mino-demo"
                session.allowCopying = false
                if run {
                    appState.store.debugProOverride = true
                    appState.protect(session)
                }
            }
        case "unlock":
            // The locked sample is unlocked here as the password prompt would do it.
            let locked = makeLockedPDF()
            do {
                _ = try await appState.documentImporter.importDocument(from: locked)
            } catch ImportError.passwordRequired(let copy) {
                if let document = try? await appState.documentImporter.unlock(copy: copy, password: "mino") {
                    appState.start(.protect, with: [document])
                }
            } catch {}
            if run, let session = appState.protectSession {
                appState.store.debugProOverride = true
                appState.protect(session)
            }
        case "files":
            appState.selectedTab = .files
        case "settings":
            appState.selectedTab = .settings
        case "paywall":
            appState.showPaywall(.tool(.merge))
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
        // Results of the tools added in 2.1.
        if Tool.organize.isAvailable, let doc = try? await importer.importDocument(from: contract) {
            let output = OutputLocation.url(folder: "Edited", fileName: "Rental Contract (edited)")
            let pages = (0..<6).map { OrganizedPage(source: .original($0)) }
            if (try? PageOrganizer.save(documentURL: doc.url, pages: pages, outputURL: output)) != nil {
                appState.toolResults.add(ToolOutput(urls: [output], kind: .edited, pageCount: 6), tool: .organize)
            }
        }
        if Tool.protect.isAvailable, let doc = try? await importer.importDocument(from: invoice) {
            let output = OutputLocation.url(folder: "Protected", fileName: "Invoice March (protected)")
            if (try? PDFProtector.protect(documentURL: doc.url, password: "mino", allowPrinting: true, allowCopying: true, outputURL: output)) != nil {
                appState.toolResults.add(
                    ToolOutput(urls: [output], kind: .protected, pageCount: 2, detail: String(localized: "Password added")),
                    tool: .protect
                )
            }
        }
        if Tool.photosToPDF.isAvailable {
            let output = OutputLocation.url(folder: "Converted", fileName: "Photos 12 Nov")
            let inputs = makeSamplePhotos().prefix(4).compactMap(PhotoInput.load(from:))
            if (try? PhotosToPDFEngine.makePDF(photos: Array(inputs), pageSize: .a4, margin: .small, outputURL: output)) != nil {
                appState.toolResults.add(ToolOutput(urls: [output], kind: .converted, pageCount: inputs.count), tool: .photosToPDF)
            }
        }
        for source in [photos, receipts] {
            if let doc = try? await importer.importDocument(from: source) {
                _ = try? await appState.compressionService.compress(document: doc, settings: CompressionQuality.medium.settings)
            }
        }
    }

    /// Pages as the document camera delivers them: cropped, straightened
    /// photos of paper, with uneven light and sensor noise.
    static func makeSampleScanPages(count: Int) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DemoScans", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (1...max(1, count)).compactMap { number in
            let url = folder.appendingPathComponent("scan-page-\(number).jpg")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            guard let data = makeSampleScanPage(number: number).jpegData(compressionQuality: 0.92),
                  (try? data.write(to: url)) != nil else { return nil }
            return url
        }
    }

    static let sampleScanLines = [
        "Thank you for your order. This invoice lists the work carried out in",
        "October at 14 Canal Street. Payment is due within thirty days.",
        "Description                               Hours       Amount",
        "Kitchen plumbing repair                    3.5       245.00",
        "Replacement tap and fittings                         89.50",
        "Bathroom sealant renewal                   1.0        70.00",
        "Call-out charge                                      35.00",
        "Subtotal                                            439.50",
        "VAT 21 percent                                       92.30",
        "Total                                               531.80",
        "Please quote the invoice number with your payment.",
    ]

    private static func makeSampleScanPage(number: Int) -> UIImage {
        let size = CGSize(width: 2480, height: 3508)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let page = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Paper under uneven light.
            let colors = [UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1).cgColor,
                          UIColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: size.width * 0.2, y: 0), end: CGPoint(x: size.width, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

            let ink = UIColor(red: 0.1, green: 0.11, blue: 0.16, alpha: 1)
            ("Invoice 2026-\(String(format: "%03d", 40 + number))" as NSString).draw(
                at: CGPoint(x: 220, y: 260),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 110), .foregroundColor: ink]
            )
            ("Morgan Building Services · page \(number)" as NSString).draw(
                at: CGPoint(x: 220, y: 420),
                withAttributes: [.font: UIFont.systemFont(ofSize: 54), .foregroundColor: ink]
            )
            UIColor(red: 0.0, green: 0.45, blue: 0.48, alpha: 1).setFill()
            context.fill(CGRect(x: 220, y: 540, width: size.width - 440, height: 8))

            var y: CGFloat = 640
            for block in 0..<4 {
                for line in sampleScanLines {
                    (line as NSString).draw(
                        at: CGPoint(x: 220, y: y),
                        withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 50, weight: .regular), .foregroundColor: ink]
                    )
                    y += 62
                }
                y += block == 3 ? 0 : 40
            }
            // A signature in blue ink.
            let signature = UIBezierPath()
            signature.move(to: CGPoint(x: 260, y: 3250))
            signature.addCurve(to: CGPoint(x: 900, y: 3230), controlPoint1: CGPoint(x: 420, y: 3050), controlPoint2: CGPoint(x: 600, y: 3400))
            signature.addCurve(to: CGPoint(x: 1150, y: 3240), controlPoint1: CGPoint(x: 980, y: 3180), controlPoint2: CGPoint(x: 1050, y: 3290))
            UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1).setStroke()
            signature.lineWidth = 9
            signature.stroke()
        }
        // Sensor noise over the whole page, so the file compresses like a photo.
        guard let cgPage = page.cgImage else { return page }
        let base = CIImage(cgImage: cgPage)
        let noise = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(translationX: CGFloat(number * 37), y: CGFloat(number * 91)))
            .cropped(to: base.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
                "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
                "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0.07),
            ])
        let composed = noise.composited(over: base)
        guard let result = CIContext().createCGImage(composed, from: base.extent) else { return page }
        return UIImage(cgImage: result)
    }

    /// "Bank Statement.pdf", locked with the password "mino".
    private static func makeLockedPDF() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DemoLocked", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Bank Statement.pdf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let plain = makeSamplePDF(name: "Bank Statement Source", pages: 3, photos: false)
        try? PDFProtector.protect(documentURL: plain, password: "mino", allowPrinting: true, allowCopying: true, outputURL: url)
        return url
    }

    /// Six sample photos in the formats people have: JPEG (two of them with an
    /// EXIF rotation), PNG and HEIC.
    static func makeSamplePhotos() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DemoPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let specs: [(name: String, size: CGSize, hue: CGFloat, type: String, orientation: Int)] = [
            ("IMG_0412.jpg", CGSize(width: 1600, height: 1200), 0.55, "public.jpeg", 1),
            ("IMG_0413.jpg", CGSize(width: 1600, height: 1200), 0.08, "public.jpeg", 6),
            ("IMG_0415.heic", CGSize(width: 1200, height: 1600), 0.33, "public.heic", 1),
            ("Screenshot.png", CGSize(width: 1179, height: 2556), 0.62, "public.png", 1),
            ("IMG_0420.jpg", CGSize(width: 1600, height: 1200), 0.92, "public.jpeg", 3),
            ("IMG_0421.jpg", CGSize(width: 1200, height: 1600), 0.75, "public.jpeg", 1),
        ]
        return specs.compactMap { spec in
            let url = folder.appendingPathComponent(spec.name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            let image = makePhoto(size: spec.size, hue: spec.hue, label: spec.name)
            guard let cgImage = image.cgImage,
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, spec.type as CFString, 1, nil) else { return nil }
            let properties: [CFString: Any] = [
                kCGImagePropertyOrientation: spec.orientation,
                kCGImageDestinationLossyCompressionQuality: 0.85,
            ]
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
            return CGImageDestinationFinalize(destination) ? url : nil
        }
    }

    /// A photo-like picture with a horizon, so its orientation is easy to judge.
    private static func makePhoto(size: CGSize, hue: CGFloat, label: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1).cgColor,
                          UIColor(hue: hue, saturation: 0.65, brightness: 0.6, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Ground and sun.
            UIColor(hue: hue, saturation: 0.5, brightness: 0.35, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.68, width: size.width, height: size.height * 0.32))
            UIColor(white: 1, alpha: 0.85).setFill()
            let sun = min(size.width, size.height) * 0.16
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.68, y: size.height * 0.16, width: sun, height: sun))
            (label as NSString).draw(
                at: CGPoint(x: size.width * 0.06, y: size.height * 0.78),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: min(size.width, size.height) * 0.07), .foregroundColor: UIColor.white]
            )
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<20_000 {
                let x = CGFloat.random(in: 0..<size.width, using: &generator)
                let y = CGFloat.random(in: 0..<size.height, using: &generator)
                UIColor(white: .random(in: 0...1, using: &generator), alpha: 0.25).setFill()
                context.fill(CGRect(x: x, y: y, width: 3, height: 3))
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
