import Foundation

// MARK: - CompletionSoundOption

enum CompletionSoundOption: String, CaseIterable {
    case off = "off"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var displayName: String {
        switch self {
        case .off: return String(localized: "オフ")
        default: return rawValue
        }
    }
}
