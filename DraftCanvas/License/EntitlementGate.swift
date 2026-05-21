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
    private let warningThreshold = 3
    private let warningStateKey = "lastTrialWarningDaysLeft"
    private init() {}

    func consumeTrialWarning() -> String? {
        guard case .trial(let daysLeft) = status, daysLeft <= warningThreshold else {
            UserDefaults.standard.removeObject(forKey: warningStateKey)
            return nil
        }
        let lastShown = UserDefaults.standard.object(forKey: warningStateKey) as? Int
        guard lastShown != daysLeft else { return nil }
        UserDefaults.standard.set(daysLeft, forKey: warningStateKey)
        return daysLeft > 0 ? "トライアル残り\(daysLeft)日" : "トライアル本日まで"
    }

    func evaluate() {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["DRAFTCANVAS_LICENSE_OVERRIDE"] {
            let trimmed = override.trimmingCharacters(in: .whitespaces).lowercased()
            switch trimmed {
            case "licensed":
                status = .licensed
                print("[EntitlementGate] DEBUG override: licensed")
                return
            case "expired":
                status = .expired
                print("[EntitlementGate] DEBUG override: expired")
                return
            case "trial":
                status = .trial(daysLeft: trialDays)
                print("[EntitlementGate] DEBUG override: trial(\(trialDays))")
                return
            case "reset":
                LicenseStore.shared.resetAll()
                print("[EntitlementGate] DEBUG override: reset Keychain → continue")
            default:
                if trimmed.hasPrefix("trial:"), let n = Int(trimmed.dropFirst("trial:".count)) {
                    status = n > 0 ? .trial(daysLeft: n) : .expired
                    print("[EntitlementGate] DEBUG override: trial(\(n))")
                    return
                }
                print("[EntitlementGate] DEBUG override: 不正値 '\(override)' → 通常評価")
            }
        }
        #endif

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

    func deactivateLicense() async {
        guard let key = LicenseStore.shared.licenseKey,
              let instanceID = LicenseStore.shared.instanceID else { return }
        try? await LicenseClient.deactivate(key: key, activationID: instanceID)
        LicenseStore.shared.resetAll()
        evaluate()
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
