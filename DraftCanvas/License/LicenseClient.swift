import Foundation

enum LicenseError: LocalizedError {
    case invalidKey
    case activationLimitReached
    case alreadyActivated
    case network(Error)
    case expired
    case revoked

    var errorDescription: String? {
        switch self {
        case .invalidKey: String(localized: "ライセンスキーが無効です")
        case .activationLimitReached: String(localized: "アクティベーション上限に達しました")
        case .alreadyActivated: String(localized: "このキーは既にアクティベート済みです")
        case .network: String(localized: "ネットワークエラーが発生しました")
        case .expired: String(localized: "ライセンスの有効期限が切れています")
        case .revoked: String(localized: "ライセンスキーが無効化されました")
        }
    }
}

struct LicenseClient {
    // URLProtocol モック差し込み用（テスト時のみ差し替え）
    nonisolated(unsafe) static var urlSession: URLSession = .shared

    static func activate(key: String) async throws -> String {
        let label = Host.current().localizedName ?? "Mac"
        let body: [String: String] = [
            "key": key,
            "organization_id": PurchaseConfig.organizationID,
            "label": label
        ]
        let data = try await post(path: "/v1/customer-portal/license-keys/activate", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.invalidKey
        }
        if let detail = json["detail"] as? String {
            let lower = detail.lowercased()
            if lower.contains("limit") || lower.contains("activation") { throw LicenseError.activationLimitReached }
            if lower.contains("already") { throw LicenseError.alreadyActivated }
            throw LicenseError.invalidKey
        }
        guard let activationID = json["id"] as? String else {
            throw LicenseError.invalidKey
        }
        return activationID
    }

    static func validate(key: String, instanceID: String) async throws -> Bool {
        let body: [String: String] = [
            "key": key,
            "organization_id": PurchaseConfig.organizationID,
            "activation_id": instanceID
        ]
        let data = try await post(path: "/v1/customer-portal/license-keys/validate", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        // Polar API バージョン差異に対応した defensive parse
        if let lk = json["license_key"] as? [String: Any], let status = lk["status"] as? String {
            return status == "granted"
        }
        if let status = json["status"] as? String { return status == "granted" }
        if let isValid = json["is_valid"] as? Bool { return isValid }
        if let valid = json["valid"] as? Bool { return valid }
        return false
    }

    static func deactivate(key: String, activationID: String) async throws {
        let body: [String: String] = [
            "key": key,
            "organization_id": PurchaseConfig.organizationID,
            "activation_id": activationID
        ]
        _ = try await post(path: "/v1/customer-portal/license-keys/deactivate", body: body)
    }

    private static func post(path: String, body: [String: String]) async throws -> Data {
        var components = URLComponents(url: PurchaseConfig.apiBase, resolvingAgainstBaseURL: false)!
        components.path = path
        guard let url = components.url else { throw LicenseError.invalidKey }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw LicenseError.invalidKey
            }
            return data
        } catch let e as LicenseError {
            throw e
        } catch {
            throw LicenseError.network(error)
        }
    }
}
