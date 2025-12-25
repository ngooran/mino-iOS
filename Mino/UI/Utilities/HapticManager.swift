//
//  HapticManager.swift
//  Mino
//
//  Haptic feedback manager
//

import UIKit

final class HapticManager: @unchecked Sendable {
    static let shared = HapticManager()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        // Prepare generators for faster response
        impactLight.prepare()
        impactMedium.prepare()
        notification.prepare()
        selection.prepare()
    }

    // MARK: - Button Interactions

    /// Light tap for button presses
    func buttonTap() {
        impactLight.impactOccurred()
    }

    /// Selection changed feedback
    func selectionChanged() {
        selection.selectionChanged()
    }

    // MARK: - Compression Feedback

    /// Medium impact when compression starts
    func compressionStart() {
        impactMedium.impactOccurred()
    }

    /// Subtle feedback at progress milestones
    func compressionProgress(at percentage: Double) {
        let milestones = [25.0, 50.0, 75.0]
        if milestones.contains(where: { abs($0 - percentage) < 1 }) {
            impactLight.impactOccurred(intensity: 0.5)
        }
    }

    /// Success notification when compression completes
    func compressionComplete() {
        notification.notificationOccurred(.success)
    }

    // MARK: - Error Feedback

    /// Error notification
    func error() {
        notification.notificationOccurred(.error)
    }

    /// Warning notification
    func warning() {
        notification.notificationOccurred(.warning)
    }

    // MARK: - Custom Impacts

    /// Heavy impact for significant actions
    func heavyImpact() {
        impactHeavy.impactOccurred()
    }

    /// Soft impact
    func softImpact() {
        impactLight.impactOccurred(intensity: 0.5)
    }
}
