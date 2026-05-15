import SwiftUI

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "appLanguage"

    @Published var locale: Locale

    enum AppLanguage: String, CaseIterable, Identifiable {
        case ja, en
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .ja: "日本語"
            case .en: "English"
            }
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        let initial: AppLanguage
        if let stored, let lang = AppLanguage(rawValue: stored) {
            initial = lang
        } else {
            let osLang = Locale.preferredLanguages.first ?? "en"
            initial = osLang.hasPrefix("ja") ? .ja : .en
            UserDefaults.standard.set(initial.rawValue, forKey: Self.storageKey)
        }
        self.locale = Locale(identifier: initial.rawValue)
        self.bundle = Self.makeBundle(for: initial.rawValue)
    }

    var current: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? "en") ?? .en }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.storageKey)
            locale = Locale(identifier: newValue.rawValue)
            bundle = Self.makeBundle(for: newValue.rawValue)
        }
    }

    private(set) var bundle: Bundle = .main

    func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }

    nonisolated static func makeBundle(for langCode: String) -> Bundle {
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let b = Bundle(path: path) { return b }
        return .main
    }
}

func L(_ key: String.LocalizationValue) -> String {
    let langCode = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    let bundle = LocalizationManager.makeBundle(for: langCode)
    return String(localized: key, bundle: bundle, locale: Locale(identifier: langCode))
}
