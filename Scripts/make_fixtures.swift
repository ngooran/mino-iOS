#!/usr/bin/env swift
//
//  make_fixtures.swift
//
//  Generates the fixture files in MinoTests/Fixtures. Run on a Mac:
//      swift Scripts/make_fixtures.swift MinoTests/Fixtures
//      python3 Scripts/make_structured_fixture.py
//  The files are committed; rerun only to change them.
//

import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MinoTests/Fixtures")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// MARK: - PDFs

/// Draws pages of text. `lines` gives the text of each page.
func makePDF(_ name: String, pages: [[String]], size: CGSize = CGSize(width: 612, height: 792)) -> URL {
    let url = output.appendingPathComponent(name)
    var box = CGRect(origin: .zero, size: size)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    for lines in pages {
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        var y = size.height - 90
        for (index, line) in lines.enumerated() {
            let font = index == 0 ? NSFont.boldSystemFont(ofSize: 24) : NSFont.systemFont(ofSize: 13)
            (line as NSString).draw(at: CGPoint(x: 72, y: y), withAttributes: [.font: font])
            y -= index == 0 ? 44 : 22
        }
        NSGraphicsContext.current = nil
        context.endPDFPage()
    }
    context.closePDF()
    return url
}

// Three plain pages.
_ = makePDF("text-3pages.pdf", pages: (1...3).map { ["Plain page \($0)", "The quick brown fox jumps over the lazy dog.", "Mino fixture, page \($0) of 3."] })

// structured.pdf (bookmarks, links, form fields) is written by make_structured_fixture.py.

// MARK: - Images

/// Four colored quadrants in stored pixel order: top-left red, top-right
/// green, bottom-left blue, bottom-right yellow.
func quadrants(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let w = CGFloat(width) / 2, h = CGFloat(height) / 2
    // CoreGraphics has its origin at the bottom left.
    let fills: [(CGRect, [CGFloat])] = [
        (CGRect(x: 0, y: h, width: w, height: h), [1, 0, 0]),
        (CGRect(x: w, y: h, width: w, height: h), [0, 1, 0]),
        (CGRect(x: 0, y: 0, width: w, height: h), [0, 0, 1]),
        (CGRect(x: w, y: 0, width: w, height: h), [1, 1, 0]),
    ]
    for (rect, rgb) in fills {
        context.setFillColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        context.fill(rect)
    }
    return context.makeImage()!
}

func writeImage(_ name: String, type: UTType, width: Int, height: Int, orientation: Int) {
    let url = output.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: orientation,
        kCGImageDestinationLossyCompressionQuality: 0.9,
    ]
    CGImageDestinationAddImage(destination, quadrants(width: width, height: height), properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
}

writeImage("photo-upright.jpg", type: .jpeg, width: 600, height: 400, orientation: 1)
writeImage("photo-rotated.jpg", type: .jpeg, width: 600, height: 400, orientation: 6)
writeImage("photo-upside-down.jpg", type: .jpeg, width: 600, height: 400, orientation: 3)
writeImage("screenshot.png", type: .png, width: 300, height: 600, orientation: 1)
writeImage("photo.heic", type: .heic, width: 400, height: 600, orientation: 1)

print("Fixtures written to \(output.path)")
