//
//  Theme.swift
//  Mino
//
//  Mino follows the system: light and dark mode, grouped backgrounds,
//  standard controls and Liquid Glass on iOS 26. Teal is the tint
//  (AccentColor asset). This file only adds the few brand pieces on top.
//

import SwiftUI

// MARK: - Colors

extension Color {
    /// App icon gradient, used for the Pro badge and Pro surfaces.
    nonisolated static let minoBrandStart = Color(red: 0.13, green: 0.26, blue: 0.50)
    nonisolated static let minoBrandEnd = Color(red: 0.07, green: 0.38, blue: 0.42)

    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

extension LinearGradient {
    static let minoBrand = LinearGradient(
        colors: [.minoBrandStart, .minoBrandEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Small components

/// Marks a feature that needs Mino Pro.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(LinearGradient.minoBrand, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Requires Mino Pro")
    }
}

/// Colored rounded-square symbol, as in the Settings app.
struct IconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The app icon, drawn from the same SwiftUI design used to export it.
struct AppIconView: View {
    var size: CGFloat = 60

    var body: some View {
        AppIconDesign(size: size)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Full-width label for primary and secondary actions.
struct ActionLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Modifiers

extension View {
    /// Card surface on grouped backgrounds.
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 26) -> some View {
        self
            .padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Prominent button: Liquid Glass on iOS 26, bordered prominent before.
    @ViewBuilder
    func primaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
        }
    }

    /// Secondary button: Liquid Glass on iOS 26, bordered before.
    @ViewBuilder
    func secondaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
        }
    }

    /// Pins actions above the home indicator, with the iOS 26 scroll edge effect.
    @ViewBuilder
    func bottomActions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom) {
                VStack(spacing: 8) { content() }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        } else {
            self.safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) { content() }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
    }
}
