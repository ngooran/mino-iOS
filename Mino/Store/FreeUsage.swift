//
//  FreeUsage.swift
//  Mino
//
//  Daily allowance of free compressions.
//

import Foundation

/// Counts free compressions per calendar day. Pro users are never limited.
@Observable
@MainActor
final class FreeUsage {

    /// Free single-file compressions per day.
    static let dailyLimit = 3

    private(set) var usedToday: Int = 0
    private var day: Date

    private enum Keys {
        static let day = "usage.day"
        static let count = "usage.count"
    }

    init() {
        let defaults = StorageRoot.defaults
        day = defaults.object(forKey: Keys.day) as? Date ?? Calendar.current.startOfDay(for: Date())
        usedToday = defaults.integer(forKey: Keys.count)
        rollOverIfNeeded()
    }

    /// Free compressions left today.
    var remaining: Int {
        max(0, Self.dailyLimit - usedToday)
    }

    /// Call when the app becomes active so a new day resets the count.
    func rollOverIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard !Calendar.current.isDate(day, inSameDayAs: today) else { return }
        day = today
        usedToday = 0
        persist()
    }

    /// Records one successful free compression.
    func recordUse() {
        rollOverIfNeeded()
        usedToday += 1
        persist()
    }

    #if DEBUG
    func reset() {
        usedToday = 0
        persist()
    }
    #endif

    private func persist() {
        StorageRoot.defaults.set(day, forKey: Keys.day)
        StorageRoot.defaults.set(usedToday, forKey: Keys.count)
    }
}
