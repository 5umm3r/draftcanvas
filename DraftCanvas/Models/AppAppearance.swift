import SwiftUI

// MARK: - App Appearance

enum AppAppearance: String {
    case light, dark

    var next: AppAppearance {
        self == .light ? .dark : .light
    }

    var systemImage: String {
        self == .light ? "sun.max" : "moon"
    }

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}
