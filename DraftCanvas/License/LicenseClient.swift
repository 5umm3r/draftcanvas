import Foundation

enum LicenseError: LocalizedError {
    case invalidKey
    case activationLimitReached
    case alreadyActivated
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidKey: String(localized: "ライセンスキーが無効です")
        case .activationLimitReached: String(localized: "アクティベーション上限に達しました")
        case .alreadyActivated: String(localized: "このキーは既にアクティベート済みです")
        case .network: String(localized: "ネットワークエラーが発生しました")
        }
    }
}

struct LicenseClient {
    private static let activateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
    private static let validateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!

    static func activate(key: String) async throws -> String {
        let instanceName = Host.current().localizedName ?? "Mac"
        let body = "license_key=\(key.urlEncoded)&instance_name=\(instanceName.urlEncoded)"
        let data = try await post(url: activateURL, body: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? String, !error.isEmpty {
            if error.lowercased().contains("limit") { throw LicenseError.activationLimitReached }
            throw LicenseError.invalidKey
        }
        guard let activated = json?["activated"] as? Bool, activated,
              let instance = json?["instance"] as? [String: Any],
              let instanceID = instance["id"] as? String else {
            throw LicenseError.invalidKey
        }
        return instanceID
    }

    static func validate(key: String, instanceID: String) async throws -> Bool {
        let body = "license_key=\(key.urlEncoded)&instance_id=\(instanceID.urlEncoded)"
        let data = try await post(url: validateURL, body: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["valid"] as? Bool ?? false
    }

    private static func post(url: URL, body: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body.data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return data
        } catch {
            throw LicenseError.network(error)
        }
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
