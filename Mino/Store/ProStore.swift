//
//  ProStore.swift
//  Mino
//
//  Mino Pro: a one-time, non-consumable in-app purchase (StoreKit 2).
//

import Foundation
import StoreKit

/// Owns everything about Mino Pro: the product, the purchase, restore,
/// and the automatic unlock for people who bought Mino when it was a paid app.
@Observable
@MainActor
final class ProStore {

    // MARK: - Configuration

    /// Product identifier of the non-consumable "Mino Pro" in-app purchase.
    static let productID = "com.applestan.Mino.pro"

    /// First build number (CFBundleVersion) released as a free download with Mino Pro.
    /// Anyone whose original download is an older build paid for the app up front
    /// and keeps every feature. Builds 1 (v1.0) and 3 (v1.2) were the paid releases.
    static let firstFreemiumBuild = 4

    // MARK: - State

    /// The Mino Pro product, once loaded from the App Store.
    private(set) var product: Product?

    /// The person bought Mino Pro (or got it through Family Sharing).
    private(set) var hasPurchasedPro = false

    /// The person bought Mino when it was a paid app.
    private(set) var isLegacyPurchaser: Bool

    /// A purchase is in progress.
    private(set) var isPurchasing = false

    #if DEBUG
    /// Debug-only switch to test free and Pro states without buying.
    var debugProOverride: Bool? {
        didSet { UserDefaults.standard.set(debugProOverride.map { $0 ? 1 : 0 } ?? -1, forKey: Keys.debugOverride) }
    }
    #endif

    /// Everything is unlocked.
    var isPro: Bool {
        #if DEBUG
        if let debugProOverride { return debugProOverride }
        #endif
        return hasPurchasedPro || isLegacyPurchaser
    }

    /// Localized price, e.g. "€6.99". Nil until the product loads.
    var displayPrice: String? { product?.displayPrice }

    // MARK: - Private

    private enum Keys {
        static let legacyPurchaser = "pro.legacyPurchaser"
        static let cachedPurchase = "pro.cachedPurchase"
        static let debugOverride = "pro.debugOverride"
    }

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        isLegacyPurchaser = defaults.bool(forKey: Keys.legacyPurchaser)
        // Show the last known state right away; StoreKit confirms it shortly after launch.
        hasPurchasedPro = defaults.bool(forKey: Keys.cachedPurchase)
        #if DEBUG
        switch defaults.object(forKey: Keys.debugOverride) as? Int {
        case 1: debugProOverride = true
        case 0: debugProOverride = false
        default: debugProOverride = nil
        }
        #endif

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refresh() }
    }

    // MARK: - Loading

    /// Loads the product and re-checks what the person owns.
    func refresh() async {
        await loadProduct()
        await updateEntitlements()
        await checkLegacyPurchase()
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    /// Reads current entitlements. Family Sharing and refunds are handled by StoreKit.
    func updateEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        hasPurchasedPro = owned
        UserDefaults.standard.set(owned, forKey: Keys.cachedPurchase)
    }

    /// Unlocks Pro for people who downloaded Mino while it was a paid app.
    /// On iOS, `originalAppVersion` is the CFBundleVersion (build number) of the first download.
    func checkLegacyPurchase() async {
        guard !isLegacyPurchaser else { return }
        guard let result = try? await AppTransaction.shared,
              case .verified(let appTransaction) = result else { return }
        // Sandbox and Xcode always report "1.0", so only trust production receipts.
        guard appTransaction.environment == .production else { return }
        let original = appTransaction.originalAppVersion
        let build: Int
        if let number = Int(original) {
            build = number
        } else if let number = Double(original), number.isFinite {
            build = Int(number)
        } else {
            return
        }
        if build < Self.firstFreemiumBuild {
            isLegacyPurchaser = true
            UserDefaults.standard.set(true, forKey: Keys.legacyPurchaser)
        }
    }

    // MARK: - Purchase

    enum PurchaseOutcome {
        case purchased
        case cancelled
        case pending
    }

    enum StoreError: LocalizedError {
        case productUnavailable
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return "Mino Pro isn't available right now. Check your internet connection and try again."
            case .verificationFailed:
                return "The App Store couldn't verify this purchase. Please try again."
            }
        }
    }

    func purchase() async throws -> PurchaseOutcome {
        if product == nil { await loadProduct() }
        guard let product else { throw StoreError.productUnavailable }

        isPurchasing = true
        defer { isPurchasing = false }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreError.verificationFailed
            }
            await transaction.finish()
            await updateEntitlements()
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// Restores purchases. Returns true when Pro is unlocked afterwards.
    @discardableResult
    func restore() async throws -> Bool {
        try await AppStore.sync()
        await updateEntitlements()
        await checkLegacyPurchase()
        return hasPurchasedPro || isLegacyPurchaser
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await updateEntitlements()
    }
}
