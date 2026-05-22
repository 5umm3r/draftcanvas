import Foundation

// MARK: - RateLimitConfirmation

struct RateLimitConfirmation: Identifiable {
    let id = UUID()
    let remainingPercent: Int
    let concurrency: Int
    let resume: () -> Void
}
