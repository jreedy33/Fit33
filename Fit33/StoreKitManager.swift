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
            AppLogger.info("StoreKit loaded \(products.count) products", category: .general)
        } catch {
            AppLogger.error("StoreKit failed to load products: \(error.localizedDescription)", category: .general)
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
            AppLogger.error("StoreKit purchase error: \(error.localizedDescription)", category: .general)
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            AppLogger.info("StoreKit purchases restored", category: .general)
        } catch {
            AppLogger.error("StoreKit restore failed: \(error.localizedDescription)", category: .general)
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
                    AppLogger.error("StoreKit transaction verification failed: \(error.localizedDescription)", category: .general)
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
