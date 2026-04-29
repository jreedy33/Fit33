import Foundation
import StoreKit

@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    
    // MARK: - Product IDs (must match App Store Connect)
    
    enum ProductID: String, CaseIterable {
        case monthlyPro = "com.gofit.app.pro.monthly"
        case yearlyPro = "com.gofit.app.pro.yearly"
    }
    
    // MARK: - Published State
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var subscriptionStatus: SubscriptionStatusInfo?
    
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
        case cancelled
    }
    
    struct SubscriptionStatusInfo {
        let productID: String
        let expirationDate: Date?
        let isInTrial: Bool
        let willAutoRenew: Bool
    }
    
    var hasActiveSubscription: Bool {
        !purchasedProductIDs.isEmpty
    }
    
    var monthlyProduct: Product? {
        products.first { $0.id == ProductID.monthlyPro.rawValue }
    }
    
    var yearlyProduct: Product? {
        products.first { $0.id == ProductID.yearlyPro.rawValue }
    }
    
    // MARK: - Private
    
    private var transactionListener: Task<Void, Error>?
    
    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await updatePurchasedProducts() }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Load Products
    
    func loadProducts() async {
        let startedAt = Date()
        do {
            let ids = ProductID.allCases.map(\.rawValue)
            let storeProducts = try await Product.products(for: Set(ids))
            products = storeProducts.sorted { $0.price < $1.price }
            AppLogger.info("StoreKit loaded \(products.count) products", category: .general)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Loading StoreKit products",
                category: .general,
                op: PerformanceSignposts.Op.iapLoadProducts.rawValue,
                endpoint: "storekit:Product.products",
                startedAt: startedAt
            )
        }
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        let startedAt = Date()

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                purchaseState = .purchased
                AppLogger.info("StoreKit purchase successful: \(product.id)", category: .general)
                return true

            case .userCancelled:
                purchaseState = .cancelled
                AppLogger.info("StoreKit purchase cancelled by user", category: .general)
                return false

            case .pending:
                purchaseState = .idle
                AppLogger.info("StoreKit purchase pending (Ask to Buy / SCA)", category: .general)
                return false

            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            // Verification failures (Apple-signed JWS rejected) and real
            // network malfunctions go to .error; transient network /
            // user-cancelled-as-thrown / Ask-to-Buy pending stay below.
            // Per MONETIZATION_AGENT invariants 32–33.
            NetworkErrorClassifier.log(
                error,
                context: "StoreKit purchase \(product.id)",
                category: .general,
                op: PerformanceSignposts.Op.iapPurchase.rawValue,
                endpoint: "storekit:Product.purchase",
                startedAt: startedAt
            )
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        let startedAt = Date()
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            AppLogger.info("StoreKit purchases restored", category: .general)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Restoring StoreKit purchases",
                category: .general,
                op: PerformanceSignposts.Op.iapRestore.rawValue,
                endpoint: "storekit:AppStore.sync",
                startedAt: startedAt
            )
            purchaseState = .failed("Could not restore purchases. Please try again.")
        }
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                let startedAt = Date()
                do {
                    let transaction = try Self.checkVerified(result)
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                } catch {
                    // Verification failure on a Transaction.updates entry
                    // is rare but real (revoked + replayed transaction).
                    // Route through classifier so a sandbox flap doesn't
                    // generate a fingerprint per user. Per MONETIZATION
                    // invariant 32.
                    NetworkErrorClassifier.log(
                        error,
                        context: "StoreKit Transaction.updates verification",
                        category: .general,
                        op: PerformanceSignposts.Op.iapEntitlementRefresh.rawValue,
                        endpoint: "storekit:Transaction.updates",
                        startedAt: startedAt
                    )
                }
            }
        }
    }
    
    // MARK: - Update Purchased Products
    
    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        var latestStatus: SubscriptionStatusInfo?
        
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            
            if transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
                
                if let expirationDate = transaction.expirationDate {
                    let isInTrial = transaction.offerType == .introductory
                    latestStatus = SubscriptionStatusInfo(
                        productID: transaction.productID,
                        expirationDate: expirationDate,
                        isInTrial: isInTrial,
                        willAutoRenew: true
                    )
                }
            }
        }
        
        if let info = latestStatus {
            var willAutoRenew = true
            if let product = products.first(where: { $0.id == info.productID }),
               let statuses = try? await product.subscription?.status {
                for status in statuses {
                    if case .verified(let renewalInfo) = status.renewalInfo {
                        willAutoRenew = renewalInfo.willAutoRenew
                        break
                    }
                }
            }
            latestStatus = SubscriptionStatusInfo(
                productID: info.productID,
                expirationDate: info.expirationDate,
                isInTrial: info.isInTrial,
                willAutoRenew: willAutoRenew
            )
        }
        
        purchasedProductIDs = purchased
        subscriptionStatus = latestStatus
        
        PremiumManager.shared.updateFromStoreKit(hasSubscription: !purchased.isEmpty)
    }
    
    // MARK: - Verification
    
    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
