import SwiftUI

struct PlaceholderAnimationView: View {
    let style: PlaceholderAnimationStyle
    let seed: Int

    var body: some View {
        switch style.resolved(seed: seed) {
        case .aurora:
            AuroraPlaceholderView(seed: seed)
        case .gridWave:
            GridWavePlaceholderView(seed: seed)
        case .wireframeRotation:
            WireframeRotationPlaceholderView(seed: seed)
        case .particleFlow:
            ParticleFlowPlaceholderView(seed: seed)
        case .scanlineSweep:
            ScanlineSweepPlaceholderView(seed: seed)
        case .mosaicPulse:
            MosaicPulsePlaceholderView(seed: seed)
        case .random:
            AuroraPlaceholderView(seed: seed)
        }
    }
}
