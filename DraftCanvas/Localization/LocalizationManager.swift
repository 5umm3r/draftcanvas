import AppKit
import SwiftUI

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "appLanguage"

    @Published var locale: Locale
    @Published var pendingRestart: Bool = false

    /// 選択中の言語。computed で UserDefaults を直読みしていると SwiftUI が
    /// 変化を購読できず、ピッカーで選んでも表示が更新されない。
    @Published var current: AppLanguage {
        didSet {
            guard current != oldValue else { return }
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
            switch current {
            case .system:
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            case .ja:
                UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
            case .en:
                UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            }
            pendingRestart = true
        }
    }

    enum AppLanguage: String, CaseIterable, Identifiable {
        case ja, en, system
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .ja: "日本語"
            case .en: "English"
            case .system: String(localized: "システム設定に従う")
            }
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        let initial: AppLanguage = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        // init 内の代入では didSet が走らないため、保存済みの値を書き戻さずに済む
        self.current = initial
        self.locale = Self.resolveLocale(for: initial)
    }

    private static func resolveLocale(for lang: AppLanguage) -> Locale {
        switch lang {
        case .ja: return Locale(identifier: "ja")
        case .en: return Locale(identifier: "en")
        case .system:
            let code = Bundle.main.preferredLocalizations.first ?? "en"
            return Locale(identifier: code)
        }
    }

    @MainActor
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

}
