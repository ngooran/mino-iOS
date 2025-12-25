//
//  Theme.swift
//  Mino
//
//  App theming and styling
//

import SwiftUI

// MARK: - Colors

extension Color {
    /// Primary accent color
    static let minoAccent = Color.accentColor

    /// Success/positive color
    static let minoSuccess = Color.green

    /// Warning color
    static let minoWarning = Color.orange

    /// Error color
    static let minoError = Color.red

    /// Secondary background
    static let minoSecondaryBackground = Color(.secondarySystemBackground)
}

// MARK: - Fonts

extension Font {
    /// Title font with rounded design
    static let minoTitle = Font.system(.title, design: .rounded, weight: .bold)

    /// Headline font with rounded design
    static let minoHeadline = Font.system(.headline, design: .rounded, weight: .semibold)

    /// Body font
    static let minoBody = Font.system(.body, design: .default, weight: .regular)

    /// Caption font
    static let minoCaption = Font.system(.caption, design: .default, weight: .regular)

    /// Monospaced digits for numbers
    static let minoNumber = Font.system(.body, design: .monospaced, weight: .medium)
}

// MARK: - Button Styles

/// Primary button style for main actions
struct MinoPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDisabled ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Secondary button style for less prominent actions
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

// MARK: - View Modifiers

extension View {
    /// Applies card styling
    func minoCard() -> some View {
        self
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Applies card styling with shadow
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
    /// Standard app animation
    static let minoStandard = Animation.easeInOut(duration: 0.2)

    /// Bounce animation for success states
    static let minoBounce = Animation.spring(response: 0.4, dampingFraction: 0.6)
}

// MARK: - Preview

#Preview("Theme Colors") {
    VStack(spacing: 20) {
        HStack {
            Circle().fill(Color.minoAccent)
            Circle().fill(Color.minoSuccess)
            Circle().fill(Color.minoWarning)
            Circle().fill(Color.minoError)
        }
        .frame(height: 50)

        Button("Primary Button") {}
            .buttonStyle(MinoPrimaryButtonStyle())

        Button("Secondary Button") {}
            .buttonStyle(MinoSecondaryButtonStyle())

        Text("Card Example")
            .minoCard()
    }
    .padding()
}
