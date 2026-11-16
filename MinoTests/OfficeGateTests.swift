//
//  OfficeGateTests.swift
//  MinoTests
//
//  The Office to PDF quality gate (ROADMAP.md, section 4, tool 9): convert a
//  folder of real documents and write, next to each PDF, what Quick Look
//  shows for the same file, so the two can be compared.
//
//  The documents are not part of the repository. Run it with a folder:
//
//    TEST_RUNNER_MINO_GATE_DIR=/path/to/documents \
//    TEST_RUNNER_MINO_GATE_OUT=/path/to/results \
//    xcodebuild test ... -only-testing:MinoTests/OfficeGateTests
//
//  Without the folder the test is skipped.
//

import PDFKit
import QuickLookThumbnailing
import XCTest
@testable import Mino

@MainActor
final class OfficeGateTests: XCTestCase {

    func testConvertDocumentsInGateFolder() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["MINO_GATE_DIR"], let output = environment["MINO_GATE_OUT"] else {
            throw XCTSkip("Set MINO_GATE_DIR and MINO_GATE_OUT to run the Office to PDF gate.")
        }
        let inputURL = URL(fileURLWithPath: input, isDirectory: true)
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil)
            .filter { ImportTypes.classify($0) == .office }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "No Office documents in \(input)")

        var report = "file\tpages\tlayout\tpaper\tscale\ttext coverage\tseconds\n"
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            // Work on a copy, as the app does.
            let copy = Scratch.directory(for: self).appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: copy)
            let pdf = outputURL.appendingPathComponent(name + ".pdf")
            let start = Date()
            do {
                let outcome = try await OfficeConverter().convert(fileURL: copy, pageSize: .a4, outputURL: pdf)
                let seconds = Date().timeIntervalSince(start)
                let coverage = Self.coverage(of: outcome.text, in: PDFDocument(url: pdf)?.string ?? "")
                report += "\(file.lastPathComponent)\t\(outcome.pageCount)\t\(outcome.layout.rawValue)\t\(Int(outcome.paper.width))x\(Int(outcome.paper.height))\t\(String(format: "%.2f", outcome.scale))\t\(String(format: "%.0f%%", coverage * 100))\t\(String(format: "%.1f", seconds))\n"
            } catch {
                report += "\(file.lastPathComponent)\tFAILED: \(error.localizedDescription)\n"
            }
            // What Quick Look shows for the same file.
            let request = QLThumbnailGenerator.Request(fileAt: copy, size: CGSize(width: 600, height: 800), scale: 1, representationTypes: .thumbnail)
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
               let png = thumbnail.uiImage.pngData() {
                try? png.write(to: outputURL.appendingPathComponent(name + ".ql.png"))
            }
        }
        try report.write(to: outputURL.appendingPathComponent("report.tsv"), atomically: true, encoding: .utf8)
        print(report)
    }

    /// Share of the words the renderer shows that are also in the PDF's text.
    static func coverage(of expected: String, in actual: String) -> Double {
        func words(_ text: String) -> [String] {
            text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
        }
        let wanted = words(expected)
        guard !wanted.isEmpty else { return 1 }
        var available: [String: Int] = [:]
        words(actual).forEach { available[$0, default: 0] += 1 }
        var found = 0
        for word in wanted where (available[word] ?? 0) > 0 {
            available[word]! -= 1
            found += 1
        }
        return Double(found) / Double(wanted.count)
    }
}
