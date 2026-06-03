import Foundation

enum PlaceholderAnimationStyle: String, CaseIterable, Identifiable {
    case random
    case aurora
    case gridWave
    case wireframeRotation
    case particleFlow
    case scanlineSweep
    case mosaicPulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .random:            return String(localized: "ランダム")
        case .aurora:            return String(localized: "オーロラ")
        case .gridWave:          return String(localized: "グリッドウェーブ")
        case .wireframeRotation: return String(localized: "ワイヤーフレーム")
        case .particleFlow:      return String(localized: "パーティクル")
        case .scanlineSweep:     return String(localized: "スキャンライン")
        case .mosaicPulse:       return String(localized: "モザイク")
        }
    }

    static let concreteStyles: [PlaceholderAnimationStyle] = [
        .aurora,
        .gridWave,
        .wireframeRotation,
        .particleFlow,
        .scanlineSweep,
        .mosaicPulse,
    ]

    func resolved(seed: Int) -> PlaceholderAnimationStyle {
        switch self {
        case .random:
            let styles = Self.concreteStyles
            let i = ((seed % styles.count) + styles.count) % styles.count
            return styles[i]
        default:
            return self
        }
    }
}
