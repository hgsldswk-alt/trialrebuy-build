import StoreKit
import SwiftUI
import Security

private enum CommerceDisk {
    static func keychain(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TrialRebuy.Entitlement",
         kSecAttrAccount as String: key]
    }

    static func load() -> Entitlement {
        let query = keychain("v1").merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new }
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let value = try? JSONDecoder().decode(Entitlement.self, from: data) { return value }
        if let data = UserDefaults.standard.data(forKey: "entitlement.v1"),
           let value = try? JSONDecoder().decode(Entitlement.self, from: data) { return value }
        return Entitlement()
    }

    static func save(_ value: Entitlement) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "entitlement.v1")
        let query = keychain("v1")
        let fields = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, fields as CFDictionary) == errSecItemNotFound {
            let item = query.merging(fields) { _, new in new }
                .merging([kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

private actor EntitlementStore {
    func load() -> Entitlement { CommerceDisk.load() }
    func save(_ value: Entitlement) { CommerceDisk.save(value) }
}

@MainActor
final class Commerce: ObservableObject {
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var products = [String: StoreKit.Product]()
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let disk = EntitlementStore()
    private var listener: Task<Void, Never>?
    private var loading = false
    private var entitlementEpoch = 0

    var hasPro: Bool { Launch.isFree || (entitlement?.hasPro(at: .now) ?? false) }

    func start() async {
        guard !loading, entitlement == nil else { return }
        loading = true
        defer { loading = false }
        if Launch.testing {
            var value = Entitlement()
            value.startPaidMode(at: Launch.arguments.contains("-expired")
                                ? Date.now.addingTimeInterval(-Entitlement.duration - 60) : .now)
            value.purchasedPro = Launch.arguments.contains("-purchased")
            entitlement = value
            return
        }
        var value = await disk.load()
        if !Launch.isFree { value.startPaidMode(at: .now) }
        entitlement = value
        await disk.save(value)
        guard !Launch.isFree else { return }
        listener = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self, case .verified(let transaction) = update else { continue }
                guard [Launch.proID, Launch.trialID].contains(transaction.productID) else { continue }
                await self.consume(transaction)
                await self.refresh()
                await transaction.finish()
            }
        }
        await refresh()
    }

    func fetchProducts() async {
        guard !Launch.testing, !Launch.isFree else { return }
        do {
            let available = try await StoreKit.Product.products(for: [Launch.proID, Launch.trialID])
            products = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        } catch {
            message = L.t("pay.offline")
        }
    }

    private func consume(_ transaction: StoreKit.Transaction) async {
        entitlementEpoch += 1
        guard var value = entitlement else { return }
        if transaction.productID == Launch.proID {
            value.purchasedPro = transaction.revocationDate == nil
        } else if transaction.productID == Launch.trialID, transaction.revocationDate == nil {
            let date = transaction.originalPurchaseDate
            value.trialClaimedAt = min(value.trialClaimedAt ?? date, date)
        }
        entitlement = value
        await disk.save(value)
    }

    private func refresh() async {
        let epoch = entitlementEpoch
        var purchase: StoreKit.Transaction?
        var uncertainPro = false
        var claimDate: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let item):
                guard item.revocationDate == nil else { continue }
                if item.productID == Launch.proID { purchase = item }
                if item.productID == Launch.trialID { claimDate = item.originalPurchaseDate }
            case .unverified(let item, _):
                if item.productID == Launch.proID { uncertainPro = true }
            }
        }
        let latest = await StoreKit.Transaction.latest(for: Launch.proID)
        guard epoch == entitlementEpoch, var value = entitlement else { return }
        if purchase != nil { value.purchasedPro = true }
        else if !uncertainPro, case .verified(let transaction)? = latest {
            value.purchasedPro = transaction.revocationDate == nil
        }
        if let claimDate { value.trialClaimedAt = min(value.trialClaimedAt ?? claimDate, claimDate) }
        entitlement = value
        await disk.save(value)
    }

    func buy(_ id: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        if Launch.testing {
            if var value = entitlement {
                if id == Launch.proID { value.purchasedPro = true }
                if id == Launch.trialID { value.trialClaimedAt = value.trialStart }
                entitlement = value
            }
            return
        }
        if products[id] == nil { await fetchProducts() }
        guard let product = products[id] else {
            message = L.t("pay.offline")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await consume(transaction)
                await transaction.finish()
            case .success(.unverified): message = L.t("pay.unverified")
            case .pending: message = L.t("pay.pending")
            case .userCancelled: break
            @unknown default: message = L.t("pay.offline")
            }
        } catch {
            message = L.t("pay.offline")
        }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            if !Launch.testing {
                try await AppStore.sync()
                await refresh()
            }
            message = L.t(entitlement?.purchasedPro == true || entitlement?.trialClaimedAt != nil
                          ? "pay.restored" : "pay.nothing")
        } catch {
            message = L.t("pay.offline")
        }
    }
}
