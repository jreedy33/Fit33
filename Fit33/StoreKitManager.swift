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
        do {
            let ids = ProductID.allCases.map(\.rawValue)
            let storeProducts = try await Product.products(for: Set(ids))
            products = storeProducts.sorted { $0.price < $1.price }
            print("📦 [StoreKit] Loaded \(products.count) products")
        } catch {
            print("📦 [StoreKit] Failed to load products: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                purchaseState = .purchased
                print("📦 [StoreKit] Purchase successful: \(product.id)")
                return true
                
            case .userCancelled:
                purchaseState = .cancelled
                print("📦 [StoreKit] Purchase cancelled by user")
                return false
                
            case .pending:
                purchaseState = .idle
                print("📦 [StoreKit] Purchase pending (Ask to Buy / SCA)")
                return false
                
            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            print("📦 [StoreKit] Purchase error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            print("📦 [StoreKit] Purchases restored")
        } catch {
            print("📦 [StoreKit] Restore failed: \(error.localizedDescription)")
            purchaseState = .failed("Could not restore purchases. Please try again.")
        }
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                } catch {
                    print("📦 [StoreKit] Transaction verification failed: \(error)")
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
