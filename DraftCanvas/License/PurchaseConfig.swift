import Foundation

enum PurchaseConfig {
    static let purchaseURL = URL(string: "https://buy.polar.sh/__REPLACE_ME__")!
    static let organizationID = "__REPLACE_ME__"

    #if POLAR_SANDBOX
    static let apiBase = URL(string: "https://sandbox-api.polar.sh")!
    #else
    static let apiBase = URL(string: "https://api.polar.sh")!
    #endif
}
