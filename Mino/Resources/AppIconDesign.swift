//
//  AppIconDesign.swift
//  Mino
//
//  App icon design using SwiftUI Canvas
//

import SwiftUI

// MARK: - Main App Icon Design

struct AppIconDesign: View {
    let size: CGFloat

    // Vibrant gradient background colors - more visible contrast
    private let gradientStart = Color(red: 0.12, green: 0.22, blue: 0.45) // Brighter blue (top-left)
    private let gradientEnd = Color(red: 0.08, green: 0.35, blue: 0.42) // Teal (bottom-right)
    private let documentColor = Color.white
    private let arrowColor = Color(red: 0.25, green: 0.75, blue: 0.75) // Bright teal

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Gradient background
            let backgroundGradient = Gradient(colors: [gradientStart, gradientEnd])
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .linearGradient(
                    backgroundGradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                )
            )

            // Squeezed document shape - BIGGER
            let docWidth: CGFloat = 420 * scale
            let docHeight: CGFloat = 540 * scale
            let curveDepth: CGFloat = 60 * scale
            let cornerRadius: CGFloat = 30 * scale

            let docLeft = center.x - docWidth / 2
            let docRight = center.x + docWidth / 2
            let docTop = center.y - docHeight / 2
            let docBottom = center.y + docHeight / 2

            // Create document path
            var docPath = Path()
            docPath.move(to: CGPoint(x: docLeft + cornerRadius, y: docTop))
            docPath.addLine(to: CGPoint(x: docRight - cornerRadius, y: docTop))
            docPath.addQuadCurve(to: CGPoint(x: docRight, y: docTop + cornerRadius), control: CGPoint(x: docRight, y: docTop))
            docPath.addQuadCurve(to: CGPoint(x: docRight, y: docBottom - cornerRadius), control: CGPoint(x: docRight - curveDepth, y: center.y))
            docPath.addQuadCurve(to: CGPoint(x: docRight - cornerRadius, y: docBottom), control: CGPoint(x: docRight, y: docBottom))
            docPath.addLine(to: CGPoint(x: docLeft + cornerRadius, y: docBottom))
            docPath.addQuadCurve(to: CGPoint(x: docLeft, y: docBottom - cornerRadius), control: CGPoint(x: docLeft, y: docBottom))
            docPath.addQuadCurve(to: CGPoint(x: docLeft, y: docTop + cornerRadius), control: CGPoint(x: docLeft + curveDepth, y: center.y))
            docPath.addQuadCurve(to: CGPoint(x: docLeft + cornerRadius, y: docTop), control: CGPoint(x: docLeft, y: docTop))
            docPath.closeSubpath()

            // PDF text for cutout
            let pdfText = Text("PDF")
                .font(.system(size: 150 * scale, weight: .black, design: .rounded))
                .foregroundColor(.black)

            // Draw document with shadow, then cutout text in a layer
            context.addFilter(.shadow(color: .black.opacity(0.5), radius: 25 * scale, x: 0, y: 10 * scale))
            context.drawLayer { layerContext in
                // Fill document
                layerContext.fill(docPath, with: .color(documentColor))

                // Cut out PDF text (no shadow on this)
                layerContext.blendMode = .destinationOut
                layerContext.draw(pdfText, at: CGPoint(x: center.x, y: center.y + 10 * scale))
            }
            context.addFilter(.shadow(color: .clear, radius: 0, x: 0, y: 0))

            // Left arrow - THICKER
            let arrowLength: CGFloat = 140 * scale
            let arrowHeadSize: CGFloat = 65 * scale
            let arrowY = center.y
            let leftArrowTip = docLeft - 20 * scale
            let leftArrowStart = leftArrowTip - arrowLength

            var leftArrowPath = Path()
            leftArrowPath.move(to: CGPoint(x: leftArrowStart, y: arrowY))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip, y: arrowY))
            leftArrowPath.move(to: CGPoint(x: leftArrowTip - arrowHeadSize, y: arrowY - arrowHeadSize * 0.55))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip, y: arrowY))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip - arrowHeadSize, y: arrowY + arrowHeadSize * 0.55))

            context.stroke(leftArrowPath, with: .color(arrowColor), style: StrokeStyle(lineWidth: 28 * scale, lineCap: .round, lineJoin: .round))

            // Right arrow - THICKER
            let rightArrowTip = docRight + 20 * scale
            let rightArrowStart = rightArrowTip + arrowLength

            var rightArrowPath = Path()
            rightArrowPath.move(to: CGPoint(x: rightArrowStart, y: arrowY))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip, y: arrowY))
            rightArrowPath.move(to: CGPoint(x: rightArrowTip + arrowHeadSize, y: arrowY - arrowHeadSize * 0.55))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip, y: arrowY))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip + arrowHeadSize, y: arrowY + arrowHeadSize * 0.55))

            context.stroke(rightArrowPath, with: .color(arrowColor), style: StrokeStyle(lineWidth: 28 * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Dark Mode Icon Design

struct AppIconDesignDark: View {
    let size: CGFloat

    // Pure black background for dark mode
    private let backgroundColor = Color.black
    private let documentColor = Color(red: 0.92, green: 0.92, blue: 0.94)
    private let arrowColor = Color(red: 0.25, green: 0.75, blue: 0.75)

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Pure black background
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(backgroundColor)
            )

            // Squeezed document shape - BIGGER
            let docWidth: CGFloat = 420 * scale
            let docHeight: CGFloat = 540 * scale
            let curveDepth: CGFloat = 60 * scale
            let cornerRadius: CGFloat = 30 * scale

            let docLeft = center.x - docWidth / 2
            let docRight = center.x + docWidth / 2
            let docTop = center.y - docHeight / 2
            let docBottom = center.y + docHeight / 2

            var docPath = Path()
            docPath.move(to: CGPoint(x: docLeft + cornerRadius, y: docTop))
            docPath.addLine(to: CGPoint(x: docRight - cornerRadius, y: docTop))
            docPath.addQuadCurve(to: CGPoint(x: docRight, y: docTop + cornerRadius), control: CGPoint(x: docRight, y: docTop))
            docPath.addQuadCurve(to: CGPoint(x: docRight, y: docBottom - cornerRadius), control: CGPoint(x: docRight - curveDepth, y: center.y))
            docPath.addQuadCurve(to: CGPoint(x: docRight - cornerRadius, y: docBottom), control: CGPoint(x: docRight, y: docBottom))
            docPath.addLine(to: CGPoint(x: docLeft + cornerRadius, y: docBottom))
            docPath.addQuadCurve(to: CGPoint(x: docLeft, y: docBottom - cornerRadius), control: CGPoint(x: docLeft, y: docBottom))
            docPath.addQuadCurve(to: CGPoint(x: docLeft, y: docTop + cornerRadius), control: CGPoint(x: docLeft + curveDepth, y: center.y))
            docPath.addQuadCurve(to: CGPoint(x: docLeft + cornerRadius, y: docTop), control: CGPoint(x: docLeft, y: docTop))
            docPath.closeSubpath()

            // PDF text for cutout
            let pdfText = Text("PDF")
                .font(.system(size: 150 * scale, weight: .black, design: .rounded))
                .foregroundColor(.black)

            // Document with glow, then cutout text in a layer
            context.addFilter(.shadow(color: arrowColor.opacity(0.4), radius: 30 * scale, x: 0, y: 0))
            context.drawLayer { layerContext in
                layerContext.fill(docPath, with: .color(documentColor))
                layerContext.blendMode = .destinationOut
                layerContext.draw(pdfText, at: CGPoint(x: center.x, y: center.y + 10 * scale))
            }
            context.addFilter(.shadow(color: .clear, radius: 0, x: 0, y: 0))

            // Left arrow - THICKER
            let arrowLength: CGFloat = 140 * scale
            let arrowHeadSize: CGFloat = 65 * scale
            let arrowY = center.y
            let leftArrowTip = docLeft - 20 * scale
            let leftArrowStart = leftArrowTip - arrowLength

            var leftArrowPath = Path()
            leftArrowPath.move(to: CGPoint(x: leftArrowStart, y: arrowY))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip, y: arrowY))
            leftArrowPath.move(to: CGPoint(x: leftArrowTip - arrowHeadSize, y: arrowY - arrowHeadSize * 0.55))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip, y: arrowY))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip - arrowHeadSize, y: arrowY + arrowHeadSize * 0.55))

            context.stroke(leftArrowPath, with: .color(arrowColor), style: StrokeStyle(lineWidth: 28 * scale, lineCap: .round, lineJoin: .round))

            // Right arrow - THICKER
            let rightArrowTip = docRight + 20 * scale
            let rightArrowStart = rightArrowTip + arrowLength

            var rightArrowPath = Path()
            rightArrowPath.move(to: CGPoint(x: rightArrowStart, y: arrowY))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip, y: arrowY))
            rightArrowPath.move(to: CGPoint(x: rightArrowTip + arrowHeadSize, y: arrowY - arrowHeadSize * 0.55))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip, y: arrowY))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip + arrowHeadSize, y: arrowY + arrowHeadSize * 0.55))

            context.stroke(rightArrowPath, with: .color(arrowColor), style: StrokeStyle(lineWidth: 28 * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Tinted Icon Design (Monochrome)

struct AppIconDesignTinted: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Dark gray background
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(Color(white: 0.12))
            )

            // Squeezed document shape - BIGGER, filled white
            let docWidth: CGFloat = 420 * scale
            let docHeight: CGFloat = 540 * scale
            let curveDepth: CGFloat = 60 * scale
            let cornerRadius: CGFloat = 30 * scale

            let docLeft = center.x - docWidth / 2
            let docRight = center.x + docWidth / 2
            let docTop = center.y - docHeight / 2
            let docBottom = center.y + docHeight / 2

            var docPath = Path()
            docPath.move(to: CGPoint(x: docLeft + cornerRadius, y: docTop))
            docPath.addLine(to: CGPoint(x: docRight - cornerRadius, y: docTop))
            docPath.addQuadCurve(to: CGPoint(x: docRight, y: docTop + cornerRadius), control: CGPoint(x: docRight, y: docTop))
            docPath.addQuadCurve(to: CGPoint(x: docRight, y: docBottom - cornerRadius), control: CGPoint(x: docRight - curveDepth, y: center.y))
            docPath.addQuadCurve(to: CGPoint(x: docRight - cornerRadius, y: docBottom), control: CGPoint(x: docRight, y: docBottom))
            docPath.addLine(to: CGPoint(x: docLeft + cornerRadius, y: docBottom))
            docPath.addQuadCurve(to: CGPoint(x: docLeft, y: docBottom - cornerRadius), control: CGPoint(x: docLeft, y: docBottom))
            docPath.addQuadCurve(to: CGPoint(x: docLeft, y: docTop + cornerRadius), control: CGPoint(x: docLeft + curveDepth, y: center.y))
            docPath.addQuadCurve(to: CGPoint(x: docLeft + cornerRadius, y: docTop), control: CGPoint(x: docLeft, y: docTop))
            docPath.closeSubpath()

            // Document filled
            context.fill(docPath, with: .color(.white))

            // "PDF" text as cutout
            let pdfText = Text("PDF")
                .font(.system(size: 150 * scale, weight: .black, design: .rounded))
                .foregroundColor(.black)

            context.blendMode = .destinationOut
            context.draw(pdfText, at: CGPoint(x: center.x, y: center.y + 10 * scale))
            context.blendMode = .normal

            // Left arrow - THICKER
            let arrowLength: CGFloat = 140 * scale
            let arrowHeadSize: CGFloat = 65 * scale
            let arrowY = center.y
            let leftArrowTip = docLeft - 20 * scale
            let leftArrowStart = leftArrowTip - arrowLength

            var leftArrowPath = Path()
            leftArrowPath.move(to: CGPoint(x: leftArrowStart, y: arrowY))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip, y: arrowY))
            leftArrowPath.move(to: CGPoint(x: leftArrowTip - arrowHeadSize, y: arrowY - arrowHeadSize * 0.55))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip, y: arrowY))
            leftArrowPath.addLine(to: CGPoint(x: leftArrowTip - arrowHeadSize, y: arrowY + arrowHeadSize * 0.55))

            context.stroke(leftArrowPath, with: .color(.white), style: StrokeStyle(lineWidth: 26 * scale, lineCap: .round, lineJoin: .round))

            // Right arrow - THICKER
            let rightArrowTip = docRight + 20 * scale
            let rightArrowStart = rightArrowTip + arrowLength

            var rightArrowPath = Path()
            rightArrowPath.move(to: CGPoint(x: rightArrowStart, y: arrowY))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip, y: arrowY))
            rightArrowPath.move(to: CGPoint(x: rightArrowTip + arrowHeadSize, y: arrowY - arrowHeadSize * 0.55))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip, y: arrowY))
            rightArrowPath.addLine(to: CGPoint(x: rightArrowTip + arrowHeadSize, y: arrowY + arrowHeadSize * 0.55))

            context.stroke(rightArrowPath, with: .color(.white), style: StrokeStyle(lineWidth: 26 * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Export View

struct AppIconExportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVariant: IconVariant = .main
    @State private var renderedImage: UIImage?

    enum IconVariant: String, CaseIterable {
        case main = "Main"
        case dark = "Dark"
        case tinted = "Tinted"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        // Variant picker
                        Picker("Variant", selection: $selectedVariant) {
                            ForEach(IconVariant.allCases, id: \.self) { variant in
                                Text(variant.rawValue).tag(variant)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Preview with iOS corner radius simulation
                        currentIconView(size: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 280 * 0.22, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                        Text("1024 x 1024 PNG")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // All variants export info
                        Text("Export each variant separately for iOS 18 dark/tinted icons")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)

                        Spacer(minLength: 20)
                    }
                    .padding()
                }

                // Sticky export button
                if let image = renderedImage {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview("Mino App Icon", image: Image(uiImage: image))
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                            Text("Export Icon")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
            }
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedVariant) {
                renderIcon()
            }
            .onAppear {
                renderIcon()
            }
        }
    }

    @ViewBuilder
    private func currentIconView(size: CGFloat) -> some View {
        switch selectedVariant {
        case .main:
            AppIconDesign(size: size)
        case .dark:
            AppIconDesignDark(size: size)
        case .tinted:
            AppIconDesignTinted(size: size)
        }
    }

    @MainActor
    private func renderIcon() {
        let content: AnyView
        switch selectedVariant {
        case .main:
            content = AnyView(AppIconDesign(size: 1024))
        case .dark:
            content = AnyView(AppIconDesignDark(size: 1024))
        case .tinted:
            content = AnyView(AppIconDesignTinted(size: 1024))
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1.0  // Exact 1024x1024 output
        renderedImage = renderer.uiImage
    }
}

// MARK: - Previews

#Preview("Main Icon") {
    AppIconDesign(size: 300)
        .clipShape(RoundedRectangle(cornerRadius: 300 * 0.22, style: .continuous))
}

#Preview("Dark Icon") {
    AppIconDesignDark(size: 300)
        .clipShape(RoundedRectangle(cornerRadius: 300 * 0.22, style: .continuous))
}

#Preview("Tinted Icon") {
    AppIconDesignTinted(size: 300)
        .clipShape(RoundedRectangle(cornerRadius: 300 * 0.22, style: .continuous))
}

#Preview("Export View") {
    AppIconExportView()
}
