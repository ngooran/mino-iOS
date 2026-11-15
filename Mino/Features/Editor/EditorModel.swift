//
//  EditorModel.swift
//  Mino
//
//  The shared page editor of Fill & Sign and Edit & Annotate: what can be
//  put on a page, and how each thing becomes a PDF annotation.
//
//  Everything added is a standard annotation (stamp, free text, ink,
//  highlight, square, circle, line), written by PDFKit. Fill & Sign
//  flattens them on save; Edit & Annotate does so on request.
//

import PDFKit
import UIKit

/// What a tap or a drag on the page does.
enum EditorTool: Hashable, Identifiable {
    // Fill & Sign
    case signature
    case initials
    case date
    case check
    case cross
    // Both
    case text
    // Edit & Annotate
    case highlight
    case draw
    case whiteout
    case image
    case rectangle
    case ellipse
    case line
    case arrow

    var id: Self { self }

    var title: String {
        switch self {
        case .signature: return String(localized: "Signature")
        case .initials: return String(localized: "Initials")
        case .date: return String(localized: "Date")
        case .check: return String(localized: "Check")
        case .cross: return String(localized: "Cross")
        case .text: return String(localized: "Text")
        case .highlight: return String(localized: "Highlight")
        case .draw: return String(localized: "Draw")
        case .whiteout: return String(localized: "White-out")
        case .image: return String(localized: "Image")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .line: return String(localized: "Line")
        case .arrow: return String(localized: "Arrow")
        }
    }

    var systemImage: String {
        switch self {
        case .signature: return "signature"
        case .initials: return "textformat.abc"
        case .date: return "calendar"
        case .check: return "checkmark"
        case .cross: return "xmark"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .draw: return "scribble"
        case .whiteout: return "rectangle.fill"
        case .image: return "photo"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        }
    }

    /// Placed with a tap. The others are drawn with a drag.
    var placesOnTap: Bool {
        switch self {
        case .signature, .initials, .date, .check, .cross, .text, .image: return true
        case .highlight, .draw, .whiteout, .rectangle, .ellipse, .line, .arrow: return false
        }
    }

    /// Uses the chosen color.
    var usesColor: Bool {
        switch self {
        case .text, .date, .draw, .highlight, .rectangle, .ellipse, .line, .arrow, .check, .cross: return true
        case .signature, .initials, .whiteout, .image: return false
        }
    }

    static func tools(for tool: Tool) -> [EditorTool] {
        tool == .fillSign
            ? [.signature, .initials, .text, .date, .check, .cross]
            : [.text, .highlight, .draw, .whiteout, .image, .rectangle, .ellipse, .arrow, .line]
    }
}

/// Colors offered for text, ink and shapes.
enum EditorColor: String, CaseIterable, Identifiable {
    case black
    case blue
    case red
    case green
    case yellow

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .black: return UIColor(red: 0.07, green: 0.08, blue: 0.1, alpha: 1)
        case .blue: return UIColor(red: 0.06, green: 0.3, blue: 0.82, alpha: 1)
        case .red: return UIColor(red: 0.84, green: 0.13, blue: 0.16, alpha: 1)
        case .green: return UIColor(red: 0.1, green: 0.55, blue: 0.24, alpha: 1)
        case .yellow: return UIColor(red: 1, green: 0.84, blue: 0.1, alpha: 1)
        }
    }

    var title: String {
        switch self {
        case .black: return String(localized: "Black")
        case .blue: return String(localized: "Blue")
        case .red: return String(localized: "Red")
        case .green: return String(localized: "Green")
        case .yellow: return String(localized: "Yellow")
        }
    }
}

/// Which stored signature a pad or a stamp is for.
enum SignatureKind: String, Identifiable, CaseIterable, Sendable {
    case signature
    case initials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signature: return String(localized: "Your Signature")
        case .initials: return String(localized: "Your Initials")
        }
    }
}

// MARK: - Annotations

/// A picture on the page: a signature, a checkmark or a photo. A stamp
/// annotation whose appearance is the image.
final class ImageStampAnnotation: PDFAnnotation {
    let image: UIImage

    init(image: UIImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = image.cgImage else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}

/// Builds the annotations the editor adds.
enum EditorAnnotations {

    static let textPadding: CGFloat = 3

    /// Free text, sized to its content.
    static func text(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: UIColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: CGRect(origin: origin, size: .zero), forType: .freeText, withProperties: nil)
        annotation.font = UIFont.systemFont(ofSize: fontSize)
        annotation.fontColor = color
        annotation.color = .clear
        annotation.alignment = .left
        annotation.contents = string
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        fit(annotation, keepingTopLeft: CGPoint(x: origin.x, y: origin.y))
        return annotation
    }

    /// Resizes a free text annotation to its text, keeping its top-left corner
    /// (page coordinates grow upward).
    static func fit(_ annotation: PDFAnnotation, keepingTopLeft corner: CGPoint) {
        let font = annotation.font ?? UIFont.systemFont(ofSize: 14)
        let text = (annotation.contents?.isEmpty == false ? annotation.contents! : " ") as NSString
        let size = text.boundingRect(
            with: CGSize(width: 2000, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).size
        let width = ceil(size.width) + textPadding * 2 + 2
        let height = ceil(size.height) + textPadding * 2
        annotation.bounds = CGRect(x: corner.x, y: corner.y - height, width: width, height: height)
    }

    static func highlight(_ rect: CGRect, color: UIColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
        annotation.color = color.withAlphaComponent(0.6)
        return annotation
    }

    /// An opaque white rectangle. It covers content; it does not remove it.
    static func whiteout(_ rect: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        annotation.color = .white
        annotation.interiorColor = .white
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        return annotation
    }

    static func shape(_ tool: EditorTool, from start: CGPoint, to end: CGPoint, color: UIColor, lineWidth: CGFloat) -> PDFAnnotation {
        let border = PDFBorder()
        border.lineWidth = lineWidth
        switch tool {
        case .line, .arrow:
            // A line's points are relative to its bounds.
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            ).insetBy(dx: -lineWidth * 4, dy: -lineWidth * 4)
            let annotation = PDFAnnotation(bounds: rect, forType: .line, withProperties: nil)
            annotation.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            annotation.endPoint = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
            annotation.color = color
            annotation.border = border
            if tool == .arrow {
                annotation.endLineStyle = .closedArrow
                annotation.interiorColor = color
            }
            return annotation
        default:
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            let annotation = PDFAnnotation(bounds: rect, forType: tool == .ellipse ? .circle : .square, withProperties: nil)
            annotation.color = color
            annotation.border = border
            return annotation
        }
    }

    /// A freehand stroke through `points` (page coordinates).
    static func ink(_ points: [CGPoint], color: UIColor, lineWidth: CGFloat) -> PDFAnnotation? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let inset = lineWidth + 2
        let bounds = CGRect(x: minX - inset, y: minY - inset, width: maxX - minX + inset * 2, height: maxY - minY + inset * 2)

        // The path lives in the annotation's own coordinates.
        let path = UIBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: CGPoint(x: first.x - bounds.minX, y: first.y - bounds.minY))
        if points.count == 1 {
            path.addLine(to: CGPoint(x: first.x - bounds.minX + 0.1, y: first.y - bounds.minY))
        }
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
        }

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = color
        let border = PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border
        annotation.add(path)
        return annotation
    }

    /// An image stamp centered on `center`. `width` is how wide the person
    /// sees it. On a page that is shown turned by `rotation` degrees the image
    /// is turned back, so it appears upright.
    static func stamp(_ image: UIImage, center: CGPoint, width: CGFloat, pageRotation rotation: Int) -> ImageStampAnnotation {
        let aspect = image.size.height / max(1, image.size.width)
        let shown = CGSize(width: width, height: width * aspect)
        let sideways = rotation % 180 != 0
        let size = sideways ? CGSize(width: shown.height, height: shown.width) : shown
        let drawn = rotation % 360 == 0 ? image : image.rotated(clockwiseDegrees: -rotation)
        return ImageStampAnnotation(
            image: drawn,
            bounds: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        )
    }

    /// A checkmark or a cross, as a small picture in the chosen color.
    static func markImage(_ tool: EditorTool, color: UIColor) -> UIImage {
        let size = CGSize(width: 96, height: 96)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            if tool == .cross {
                path.move(to: CGPoint(x: 20, y: 20)); path.addLine(to: CGPoint(x: 76, y: 76))
                path.move(to: CGPoint(x: 76, y: 20)); path.addLine(to: CGPoint(x: 20, y: 76))
            } else {
                path.move(to: CGPoint(x: 16, y: 52)); path.addLine(to: CGPoint(x: 38, y: 74)); path.addLine(to: CGPoint(x: 80, y: 22))
            }
            path.lineWidth = 11
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }
    }

    /// Text as a picture, for pages that are shown turned: free text would
    /// follow the page and lie on its side.
    static func textImage(_ string: String, fontSize: CGFloat, color: UIColor) -> UIImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize * 3), .foregroundColor: color]
        let text = string as NSString
        let size = text.boundingRect(
            with: CGSize(width: 6000, height: 6000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil
        ).size
        let canvas = CGSize(width: ceil(size.width) + 12, height: ceil(size.height) + 12)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            text.draw(in: CGRect(x: 6, y: 6, width: size.width, height: size.height), withAttributes: attributes)
        }
    }
}

extension UIImage {
    /// The image turned clockwise by a multiple of 90 degrees.
    func rotated(clockwiseDegrees degrees: Int) -> UIImage {
        let turns = ((degrees % 360) + 360) % 360
        guard turns != 0 else { return self }
        let sideways = turns % 180 != 0
        let newSize = sideways ? CGSize(width: size.height, height: size.width) : size
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            context.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 180)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
