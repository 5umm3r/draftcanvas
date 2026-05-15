import Foundation

enum EntitlementStatus: Equatable {
    case trial(daysLeft: Int)
    case licensed
    case expired
}

@MainActor
final class EntitlementGate: ObservableObject {
    static let shared = EntitlementGate()

    @Published private(set) var status: EntitlementStatus = .trial(daysLeft: 14)
    @Published var showLicensePrompt = false
    @Published var showLicenseSheet = false
    @Published var licenseError: String?
    @Published var isActivating = false

    private let trialDays = 14
    private init() {}

    func evaluate() {
        let store = LicenseStore.shared

        if let key = store.licenseKey, let instanceID = store.instanceID {
            status = .licensed
            Task { await backgroundValidate(key: key, instanceID: instanceID) }
            return
        }

        if store.detectClockRollback() {
            status = .expired
            return
        }
        let startDate = store.loadOrInitTrial()
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        let remaining = max(0, trialDays - elapsed)
        status = remaining > 0 ? .trial(daysLeft: remaining) : .expired
    }

    var isPremiumUnlocked: Bool {
        switch status {
        case .trial, .licensed: true
        case .expired: false
        }
    }

    func requireUnlocked() -> Bool {
        if isPremiumUnlocked { return true }
        showLicensePrompt = true
        return false
    }

    func activateLicense(key: String) async {
        isActivating = true
        licenseError = nil
        defer { isActivating = false }
        do {
            let instanceID = try await LicenseClient.activate(key: key)
            let store = LicenseStore.shared
            store.licenseKey = key
            store.instanceID = instanceID
            status = .licensed
            showLicensePrompt = false
        } catch let e as LicenseError {
            licenseError = e.errorDescription
        } catch {
            licenseError = "ネットワークエラーが発生しました"
        }
    }

    private func backgroundValidate(key: String, instanceID: String) async {
        guard let valid = try? await LicenseClient.validate(key: key, instanceID: instanceID) else { return }
        if !valid {
            LicenseStore.shared.licenseKey = nil
            LicenseStore.shared.deleteItem(account: "instanceID")
            evaluate()
        }
    }
}
