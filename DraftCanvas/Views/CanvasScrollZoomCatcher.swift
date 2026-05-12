import SwiftUI

struct CanvasScrollZoomCatcher: View {
    let onScroll: (Double) -> Void
    @State private var lastMagnification: CGFloat = 1.0

    var body: some View {
        Color.clear
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = log(Double(value / lastMagnification))
                        lastMagnification = value
                        onScroll(delta)
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
    }
}
