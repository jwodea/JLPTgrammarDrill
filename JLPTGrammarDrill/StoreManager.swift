import Foundation
import StoreKit

/// StoreKit 2 manager for the single non-consumable "Unlock Full Version" IAP.
/// Mirrors entitlement state to UserDefaults so that synchronous, non-`@Observable`
/// callers (loaders, static helpers) can gate content without re-querying StoreKit.
@MainActor
@Observable
final class StoreManager {
    /// Single non-consumable product ID configured in App Store Connect.
    static let unlockProductID = "com.nogawall.jlptgrammardrill.fullunlock"

    /// UserDefaults key mirroring the entitlement. Read by `Entitlement.isFullUnlocked`
    /// from any context (including non-MainActor static code paths).
    static let unlockedDefaultsKey = "isFullVersionUnlocked"

    enum PurchaseState {
        case idle
        case loading
        case purchasing
        case restoring
        case success
        case failed(String)
        case cancelled
    }

    var product: Product?
    var isUnlocked: Bool {
        didSet {
            UserDefaults.standard.set(isUnlocked, forKey: Self.unlockedDefaultsKey)
        }
    }
    var state: PurchaseState = .idle

    @ObservationIgnored nonisolated(unsafe) private var transactionListener: Task<Void, Never>?

    init() {
        self.isUnlocked = UserDefaults.standard.bool(forKey: Self.unlockedDefaultsKey)
        startTransactionListener()
        Task { await refresh() }
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Localized display price from StoreKit. `nil` while the product hasn't loaded —
    /// callers should hide the price UI until it resolves so users in non-JPY storefronts
    /// never see a Yen fallback during the brief load.
    var displayPrice: String? {
        product?.displayPrice
    }

    func refresh() async {
        await loadProduct()
        await updateEntitlement()
    }

    func loadProduct() async {
        state = .loading
        do {
            let products = try await Product.products(for: [Self.unlockProductID])
            product = products.first
            if product == nil {
                state = .failed("The full-version product isn't available from the App Store right now. Please try again later.")
            } else {
                state = .idle
            }
        } catch {
            state = .failed("Couldn't load product: \(error.localizedDescription)")
        }
    }

    /// Re-derive entitlement from `Transaction.currentEntitlements`. Authoritative source.
    func updateEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.unlockProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    func purchase() async {
        guard let product else {
            state = .failed("Product unavailable. Check your connection and try again.")
            return
        }
        state = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isUnlocked = true
                    state = .success
                } else {
                    state = .failed("Purchase couldn't be verified.")
                }
            case .userCancelled:
                state = .cancelled
            case .pending:
                state = .failed("Your purchase is pending approval (e.g. Ask to Buy). It will unlock automatically once approved.")
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        state = .restoring
        do {
            try await AppStore.sync()
            await updateEntitlement()
            state = isUnlocked ? .success : .failed("No previous purchase found.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func startTransactionListener() {
        transactionListener = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.updateEntitlement()
                }
            }
        }
    }
}
