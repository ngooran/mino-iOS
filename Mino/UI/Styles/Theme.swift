//
//  Theme.swift
//  Mino
//
//  App theming and styling - Cool & Professional palette
//

import SwiftUI

// MARK: - Liquid Glass Support (iOS 26+)

extension View {
    /// Applies Liquid Glass effect on iOS 26+, falls back to dark card on older versions
    @ViewBuilder
    func minoGlass(in cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(Color.minoCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.minoCardBorder, lineWidth: 1)
                )
        }
    }

    /// Applies interactive Liquid Glass effect (for buttons) on iOS 26+
    @ViewBuilder
    func minoGlassInteractive(in cornerRadius: CGFloat = 14) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(Color.minoCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.minoCardBorder, lineWidth: 1)
                )
        }
    }

    /// Applies tinted Liquid Glass effect on iOS 26+
    @ViewBuilder
    func minoGlassTinted(_ color: Color, in cornerRadius: CGFloat = 14) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(color), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                )
        }
    }

    /// Applies accent-tinted interactive Liquid Glass for primary buttons
    @ViewBuilder
    func minoGlassAccentButton(in cornerRadius: CGFloat = 14) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(Color.minoAccent).interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(Color.minoAccent)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Applies toolbar styling - Liquid Glass on iOS 26+, dark background on older
    @ViewBuilder
    func minoToolbarStyle() -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26: Let system handle Liquid Glass automatically
            self
        } else {
            // Older iOS: Apply dark theme toolbar background
            self
                .toolbarBackground(Color.minoHeroBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    /// Applies Liquid Glass to a panel/container background on iOS 26+
    @ViewBuilder
    func minoGlassPanel() -> some View {
        if #available(iOS 26.0, *) {
            self.background {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Rectangle())
            }
        } else {
            self.background(Color.minoHeroBackground)
        }
    }
}

// MARK: - Colors

extension Color {
    // Primary - Deep blue/indigo
    static let minoPrimary = Color(red: 0.18, green: 0.32, blue: 0.52)
    static let minoSecondary = Color(red: 0.25, green: 0.45, blue: 0.65)

    // Accent - Teal
    static let minoAccent = Color(red: 0.20, green: 0.68, blue: 0.68)
    static let minoAccentLight = Color(red: 0.30, green: 0.78, blue: 0.78)

    // Semantic colors
    static let minoSuccess = Color(red: 0.20, green: 0.72, blue: 0.55)
    static let minoWarning = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let minoError = Color(red: 0.90, green: 0.35, blue: 0.40)

    // Surface colors
    static let minoSurface = Color.white.opacity(0.08)
    static let minoSurfaceElevated = Color.white.opacity(0.12)

    // Background
    static let minoSecondaryBackground = Color(.secondarySystemBackground)

    // Dark theme backgrounds (distinct shades)
    /// Main background - darkest shade (#0A0E14)
    static let minoBackground = Color(red: 0.039, green: 0.055, blue: 0.078)
    /// Hero card background - medium dark (#141B24)
    static let minoHeroBackground = Color(red: 0.078, green: 0.106, blue: 0.141)
    /// List item card background - slightly lighter (#1A2332)
    static let minoCardBackground = Color(red: 0.102, green: 0.137, blue: 0.196)
    /// Card border color
    static let minoCardBorder = Color.white.opacity(0.08)

    // Gradients
    static var minoGradient: LinearGradient {
        LinearGradient(
            colors: [minoPrimary, minoSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var minoAccentGradient: LinearGradient {
        LinearGradient(
            colors: [minoAccent, minoAccentLight],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Fonts

extension Font {
    // Display fonts for hero sections
    static let minoDisplay = Font.system(size: 40, weight: .bold, design: .rounded)
    static let minoDisplaySmall = Font.system(size: 28, weight: .bold, design: .rounded)

    // Title font with rounded design
    static let minoTitle = Font.system(.title, design: .rounded, weight: .bold)

    // Headline font with rounded design
    static let minoHeadline = Font.system(.headline, design: .rounded, weight: .semibold)

    // Body font
    static let minoBody = Font.system(.body, design: .default, weight: .regular)

    // Caption font
    static let minoCaption = Font.system(.caption, design: .default, weight: .regular)

    // Monospaced digits for numbers
    static let minoNumber = Font.system(.body, design: .monospaced, weight: .medium)

    // Stats/large numbers
    static let minoStats = Font.system(.title2, design: .monospaced, weight: .bold)
}

// MARK: - Button Styles

/// Glass-style primary button with gradient
struct MinoGlassButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isDisabled
                                ? AnyShapeStyle(Color.gray.opacity(0.5))
                                : AnyShapeStyle(Color.minoAccentGradient.opacity(0.9))
                        )
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .foregroundStyle(.white)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .shadow(color: Color.minoAccent.opacity(0.3), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.minoQuick, value: configuration.isPressed)
    }
}

/// Secondary glass button style
struct MinoSecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.minoSurface)
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
            }
            .foregroundStyle(.primary)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.minoQuick, value: configuration.isPressed)
    }
}

/// Legacy primary button style
struct MinoPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDisabled ? Color.gray : Color.minoAccent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Legacy secondary button style
struct MinoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.2))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Hero Background

/// Background with the MinoHeroImage as a subtle element at the bottom
struct MinoHeroBackgroundModifier: ViewModifier {
    var imageOpacity: Double = 0.4
    var height: CGFloat = 300

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Base background color
                    Color.minoBackground

                    // Hero image at the bottom
                    VStack {
                        Spacer()

                        Image("MinoHeroImage")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: height)
                            .clipped()
                            .mask(
                                // Gradient mask to fade out at top
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .clear, location: 0.1),
                                        .init(color: .white.opacity(0.3), location: 0.3),
                                        .init(color: .white.opacity(0.7), location: 0.5),
                                        .init(color: .white, location: 0.7),
                                        .init(color: .white, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(imageOpacity)
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    /// Replaces background with minoBackground + subtle hero image at bottom
    func minoHeroBackground(imageOpacity: Double = 0.4, height: CGFloat = 300) -> some View {
        modifier(MinoHeroBackgroundModifier(imageOpacity: imageOpacity, height: height))
    }
}

// MARK: - View Modifiers

/// Glass card styling modifier
struct MinoGlassCardModifier: ViewModifier {
    var isElevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isElevated ? Color.minoSurfaceElevated : Color.minoSurface)
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
            }
            .shadow(
                color: .black.opacity(isElevated ? 0.12 : 0.08),
                radius: isElevated ? 16 : 12,
                x: 0,
                y: isElevated ? 8 : 4
            )
    }
}

extension View {
    /// Applies glass card styling
    func minoGlassCard(elevated: Bool = false) -> some View {
        modifier(MinoGlassCardModifier(isElevated: elevated))
    }

    /// Applies legacy card styling
    func minoCard() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Applies legacy card styling with shadow
    func minoCardWithShadow() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Animation

extension Animation {
    /// Quick micro-interaction
    static let minoQuick = Animation.easeOut(duration: 0.15)

    /// Standard spring animation
    static let minoSpring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Standard app animation
    static let minoStandard = Animation.easeInOut(duration: 0.2)

    /// Bounce animation for success states
    static let minoBounce = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Celebration animation
    static let minoCelebrate = Animation.spring(response: 0.5, dampingFraction: 0.5)
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(spacing: 20) {
            // Color palette
            Text("Color Palette")
                .font(.headline)

            HStack(spacing: 12) {
                VStack {
                    Circle().fill(Color.minoPrimary)
                    Text("Primary").font(.caption2)
                }
                VStack {
                    Circle().fill(Color.minoSecondary)
                    Text("Secondary").font(.caption2)
                }
                VStack {
                    Circle().fill(Color.minoAccent)
                    Text("Accent").font(.caption2)
                }
                VStack {
                    Circle().fill(Color.minoSuccess)
                    Text("Success").font(.caption2)
                }
            }
            .frame(height: 70)

            // Gradient
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.minoGradient)
                .frame(height: 60)
                .overlay {
                    Text("Gradient")
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }

            // Buttons
            Text("Buttons")
                .font(.headline)

            Button("Glass Primary Button") {}
                .buttonStyle(MinoGlassButtonStyle())

            Button("Glass Secondary Button") {}
                .buttonStyle(MinoSecondaryGlassButtonStyle())

            // Cards
            Text("Cards")
                .font(.headline)

            Text("Glass Card")
                .frame(maxWidth: .infinity)
                .minoGlassCard()

            Text("Elevated Glass Card")
                .frame(maxWidth: .infinity)
                .minoGlassCard(elevated: true)
        }
        .padding()
    }
    .background(Color.minoGradient.opacity(0.3))
}
