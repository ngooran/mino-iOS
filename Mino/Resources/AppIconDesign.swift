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

    // Color palette matching the app theme
    private let primaryColor = Color(red: 0.18, green: 0.32, blue: 0.52)
    private let secondaryColor = Color(red: 0.25, green: 0.45, blue: 0.65)
    private let accentColor = Color(red: 0.20, green: 0.68, blue: 0.68)
    private let accentLight = Color(red: 0.30, green: 0.78, blue: 0.78)

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Background gradient
            let backgroundGradient = Gradient(colors: [primaryColor, secondaryColor])
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .linearGradient(
                    backgroundGradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                )
            )

            // Document shape (rounded rectangle) - centered
            let docWidth: CGFloat = 480 * scale
            let docHeight: CGFloat = 620 * scale
            let docX = center.x - docWidth / 2
            let docY = center.y - docHeight / 2

            // Document shadow/glow
            context.addFilter(.shadow(color: .black.opacity(0.3), radius: 20 * scale, x: 0, y: 10 * scale))

            // Document background
            let docRect = CGRect(x: docX, y: docY, width: docWidth, height: docHeight)
            let docPath = Path(roundedRect: docRect, cornerRadius: 40 * scale)

            context.fill(docPath, with: .color(.white))

            // Reset shadow
            context.addFilter(.shadow(color: .clear, radius: 0, x: 0, y: 0))

            // Folded corner
            let foldSize: CGFloat = 100 * scale
            var foldPath = Path()
            foldPath.move(to: CGPoint(x: docX + docWidth - foldSize, y: docY))
            foldPath.addLine(to: CGPoint(x: docX + docWidth, y: docY + foldSize))
            foldPath.addLine(to: CGPoint(x: docX + docWidth, y: docY))
            foldPath.closeSubpath()

            context.fill(foldPath, with: .color(Color(white: 0.9)))

            // Fold crease line
            var creasePath = Path()
            creasePath.move(to: CGPoint(x: docX + docWidth - foldSize, y: docY))
            creasePath.addLine(to: CGPoint(x: docX + docWidth, y: docY + foldSize))

            context.stroke(creasePath, with: .color(Color(white: 0.75)), lineWidth: 2 * scale)

            // Zipper track (vertical line down the middle)
            let zipperX = center.x
            let zipperTop = docY + 120 * scale
            let zipperBottom = docY + docHeight - 80 * scale

            // Zipper track background
            var zipperTrack = Path()
            zipperTrack.addRoundedRect(
                in: CGRect(
                    x: zipperX - 20 * scale,
                    y: zipperTop,
                    width: 40 * scale,
                    height: zipperBottom - zipperTop
                ),
                cornerSize: CGSize(width: 20 * scale, height: 20 * scale)
            )

            let zipperGradient = Gradient(colors: [accentColor, accentLight])
            context.fill(
                zipperTrack,
                with: .linearGradient(
                    zipperGradient,
                    startPoint: CGPoint(x: zipperX, y: zipperTop),
                    endPoint: CGPoint(x: zipperX, y: zipperBottom)
                )
            )

            // Zipper teeth
            let toothCount = 8
            let toothSpacing = (zipperBottom - zipperTop - 80 * scale) / CGFloat(toothCount - 1)

            for i in 0..<toothCount {
                let toothY = zipperTop + 40 * scale + CGFloat(i) * toothSpacing

                // Left tooth
                var leftTooth = Path()
                leftTooth.addRoundedRect(
                    in: CGRect(
                        x: zipperX - 50 * scale,
                        y: toothY - 8 * scale,
                        width: 35 * scale,
                        height: 16 * scale
                    ),
                    cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
                )
                context.fill(leftTooth, with: .color(Color(white: 0.85)))

                // Right tooth
                var rightTooth = Path()
                rightTooth.addRoundedRect(
                    in: CGRect(
                        x: zipperX + 15 * scale,
                        y: toothY - 8 * scale,
                        width: 35 * scale,
                        height: 16 * scale
                    ),
                    cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
                )
                context.fill(rightTooth, with: .color(Color(white: 0.85)))
            }

            // Zipper pull
            let pullY = zipperTop + 60 * scale
            var pullPath = Path()
            pullPath.addEllipse(in: CGRect(
                x: zipperX - 28 * scale,
                y: pullY - 28 * scale,
                width: 56 * scale,
                height: 56 * scale
            ))

            context.addFilter(.shadow(color: .black.opacity(0.2), radius: 4 * scale, x: 0, y: 2 * scale))
            context.fill(pullPath, with: .color(.white))
            context.addFilter(.shadow(color: .clear, radius: 0, x: 0, y: 0))

            // Pull ring
            var ringPath = Path()
            ringPath.addEllipse(in: CGRect(
                x: zipperX - 16 * scale,
                y: pullY - 16 * scale,
                width: 32 * scale,
                height: 32 * scale
            ))

            context.stroke(
                ringPath,
                with: .linearGradient(
                    zipperGradient,
                    startPoint: CGPoint(x: zipperX - 16 * scale, y: pullY),
                    endPoint: CGPoint(x: zipperX + 16 * scale, y: pullY)
                ),
                lineWidth: 6 * scale
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Dark Mode Icon Design

struct AppIconDesignDark: View {
    let size: CGFloat

    private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.12)
    private let accentColor = Color(red: 0.25, green: 0.75, blue: 0.75)
    private let accentLight = Color(red: 0.35, green: 0.85, blue: 0.85)

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Pure black background
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(backgroundColor)
            )

            // Document shape - centered
            let docWidth: CGFloat = 480 * scale
            let docHeight: CGFloat = 620 * scale
            let docX = center.x - docWidth / 2
            let docY = center.y - docHeight / 2

            let docRect = CGRect(x: docX, y: docY, width: docWidth, height: docHeight)
            let docPath = Path(roundedRect: docRect, cornerRadius: 40 * scale)

            // Document with subtle border
            context.fill(docPath, with: .color(Color(white: 0.15)))
            context.stroke(docPath, with: .color(Color(white: 0.25)), lineWidth: 2 * scale)

            // Folded corner
            let foldSize: CGFloat = 100 * scale
            var foldPath = Path()
            foldPath.move(to: CGPoint(x: docX + docWidth - foldSize, y: docY))
            foldPath.addLine(to: CGPoint(x: docX + docWidth, y: docY + foldSize))
            foldPath.addLine(to: CGPoint(x: docX + docWidth, y: docY))
            foldPath.closeSubpath()

            context.fill(foldPath, with: .color(Color(white: 0.2)))

            // Zipper track
            let zipperX = center.x
            let zipperTop = docY + 120 * scale
            let zipperBottom = docY + docHeight - 80 * scale

            var zipperTrack = Path()
            zipperTrack.addRoundedRect(
                in: CGRect(
                    x: zipperX - 20 * scale,
                    y: zipperTop,
                    width: 40 * scale,
                    height: zipperBottom - zipperTop
                ),
                cornerSize: CGSize(width: 20 * scale, height: 20 * scale)
            )

            let zipperGradient = Gradient(colors: [accentColor, accentLight])
            context.fill(
                zipperTrack,
                with: .linearGradient(
                    zipperGradient,
                    startPoint: CGPoint(x: zipperX, y: zipperTop),
                    endPoint: CGPoint(x: zipperX, y: zipperBottom)
                )
            )

            // Zipper teeth
            let toothCount = 8
            let toothSpacing = (zipperBottom - zipperTop - 80 * scale) / CGFloat(toothCount - 1)

            for i in 0..<toothCount {
                let toothY = zipperTop + 40 * scale + CGFloat(i) * toothSpacing

                var leftTooth = Path()
                leftTooth.addRoundedRect(
                    in: CGRect(x: zipperX - 50 * scale, y: toothY - 8 * scale, width: 35 * scale, height: 16 * scale),
                    cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
                )
                context.fill(leftTooth, with: .color(Color(white: 0.3)))

                var rightTooth = Path()
                rightTooth.addRoundedRect(
                    in: CGRect(x: zipperX + 15 * scale, y: toothY - 8 * scale, width: 35 * scale, height: 16 * scale),
                    cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
                )
                context.fill(rightTooth, with: .color(Color(white: 0.3)))
            }

            // Zipper pull
            let pullY = zipperTop + 60 * scale
            var pullPath = Path()
            pullPath.addEllipse(in: CGRect(
                x: zipperX - 28 * scale, y: pullY - 28 * scale, width: 56 * scale, height: 56 * scale
            ))

            context.fill(pullPath, with: .color(Color(white: 0.2)))

            var ringPath = Path()
            ringPath.addEllipse(in: CGRect(
                x: zipperX - 16 * scale, y: pullY - 16 * scale, width: 32 * scale, height: 32 * scale
            ))

            context.stroke(ringPath, with: .color(accentLight), lineWidth: 6 * scale)
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

            // Document shape - centered
            let docWidth: CGFloat = 480 * scale
            let docHeight: CGFloat = 620 * scale
            let docX = center.x - docWidth / 2
            let docY = center.y - docHeight / 2

            let docRect = CGRect(x: docX, y: docY, width: docWidth, height: docHeight)
            let docPath = Path(roundedRect: docRect, cornerRadius: 40 * scale)

            context.stroke(docPath, with: .color(.white), lineWidth: 4 * scale)

            // Folded corner
            let foldSize: CGFloat = 100 * scale
            var creasePath = Path()
            creasePath.move(to: CGPoint(x: docX + docWidth - foldSize, y: docY))
            creasePath.addLine(to: CGPoint(x: docX + docWidth, y: docY + foldSize))
            context.stroke(creasePath, with: .color(.white), lineWidth: 3 * scale)

            // Zipper track
            let zipperX = center.x
            let zipperTop = docY + 120 * scale
            let zipperBottom = docY + docHeight - 80 * scale

            var zipperTrack = Path()
            zipperTrack.addRoundedRect(
                in: CGRect(x: zipperX - 20 * scale, y: zipperTop, width: 40 * scale, height: zipperBottom - zipperTop),
                cornerSize: CGSize(width: 20 * scale, height: 20 * scale)
            )

            context.fill(zipperTrack, with: .color(.white))

            // Zipper teeth
            let toothCount = 8
            let toothSpacing = (zipperBottom - zipperTop - 80 * scale) / CGFloat(toothCount - 1)

            for i in 0..<toothCount {
                let toothY = zipperTop + 40 * scale + CGFloat(i) * toothSpacing

                var leftTooth = Path()
                leftTooth.addRoundedRect(
                    in: CGRect(x: zipperX - 50 * scale, y: toothY - 8 * scale, width: 35 * scale, height: 16 * scale),
                    cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
                )
                context.fill(leftTooth, with: .color(.white.opacity(0.6)))

                var rightTooth = Path()
                rightTooth.addRoundedRect(
                    in: CGRect(x: zipperX + 15 * scale, y: toothY - 8 * scale, width: 35 * scale, height: 16 * scale),
                    cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
                )
                context.fill(rightTooth, with: .color(.white.opacity(0.6)))
            }

            // Zipper pull
            let pullY = zipperTop + 60 * scale
            var pullPath = Path()
            pullPath.addEllipse(in: CGRect(
                x: zipperX - 28 * scale, y: pullY - 28 * scale, width: 56 * scale, height: 56 * scale
            ))

            context.fill(pullPath, with: .color(Color(white: 0.12)))
            context.stroke(pullPath, with: .color(.white), lineWidth: 4 * scale)

            var ringPath = Path()
            ringPath.addEllipse(in: CGRect(
                x: zipperX - 14 * scale, y: pullY - 14 * scale, width: 28 * scale, height: 28 * scale
            ))
            context.stroke(ringPath, with: .color(.white), lineWidth: 4 * scale)
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
            VStack(spacing: 32) {
                // Variant picker
                Picker("Variant", selection: $selectedVariant) {
                    ForEach(IconVariant.allCases, id: \.self) { variant in
                        Text(variant.rawValue).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Preview with iOS corner radius simulation
                currentIconView(size: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 280 * 0.22, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                Text("1024 x 1024 PNG")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Export button
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
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // All variants export info
                Text("Export each variant separately for iOS 18 dark/tinted icons")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical)
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
