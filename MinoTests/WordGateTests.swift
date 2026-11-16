//
//  WordGateTests.swift
//  MinoTests
//
//  The PDF to Word quality gate (ROADMAP.md, section 4, tool 10): convert a
//  folder of real PDFs to .docx and to text, so the results can be judged.
//
//    TEST_RUNNER_MINO_WORD_GATE_DIR=/path/to/pdfs \
//    TEST_RUNNER_MINO_WORD_GATE_OUT=/path/to/results \
//    xcodebuild test ... -only-testing:MinoTests/WordGateTests
//
//  Without the folder the test is skipped.
//

import PDFKit
import XCTest
@testable import Mino

final class WordGateTests: XCTestCase {

    func testConvertPDFsInGateFolder() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["MINO_WORD_GATE_DIR"], let output = environment["MINO_WORD_GATE_OUT"] else {
            throw XCTSkip("Set MINO_WORD_GATE_DIR and MINO_WORD_GATE_OUT to run the PDF to Word gate.")
        }
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: input, isDirectory: true), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        let options = environment["MINO_WORD_GATE_OPTIONS"] ?? PDFToWordEngine.wordOptions

        var report = "file\tpages\tdocx bytes\tseconds\ttext chars\n"
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let start = Date()
            do {
                let docx = outputURL.appendingPathComponent(name + ".docx")
                let pages = try PDFToWordEngine.convertToWord(documentURL: file, outputURL: docx, readScans: true, options: options)
                let seconds = Date().timeIntervalSince(start)
                let text = try PDFToWordEngine.text(of: file, readScans: true)
                try text.write(to: outputURL.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
                let size = (try FileManager.default.attributesOfItem(atPath: docx.path)[.size] as? Int) ?? 0
                report += "\(file.lastPathComponent)\t\(pages)\t\(size)\t\(String(format: "%.1f", seconds))\t\(text.count)\n"
            } catch {
                report += "\(file.lastPathComponent)\tFAILED: \(error.localizedDescription)\n"
            }
        }
        try report.write(to: outputURL.appendingPathComponent("report.tsv"), atomically: true, encoding: .utf8)
        print(report)
    }
}
