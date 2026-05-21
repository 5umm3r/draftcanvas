import Foundation

enum PurchaseConfig {
    static let purchaseURL = URL(string: "https://buy.polar.sh/polar_cl_e0kuTw7J7RdVzmUVjPJs96OJACcY1VCFkIkpk2ZYgik")!
    static let organizationID = "bf506f52-e02c-48d7-be84-6843c49ee7a8"

    #if POLAR_SANDBOX
    static let apiBase = URL(string: "https://sandbox-api.polar.sh")!
    #else
    static let apiBase = URL(string: "https://api.polar.sh")!
    #endif
}
