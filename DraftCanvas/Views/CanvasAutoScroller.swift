import AppKit

@MainActor
final class CanvasAutoScroller {
    weak var hostView: NSView?
    private var timer: Timer?
    private(set) var velocity: CGFloat = 0
    private let edgeThreshold: CGFloat = 60
    private let maxSpeed: CGFloat = 18

    func updateVelocity(mouseY y: CGFloat, viewHeight h: CGFloat) {
        if y < edgeThreshold {
            velocity = -maxSpeed * (1.0 - y / edgeThreshold)
        } else if y > h - edgeThreshold {
            velocity = maxSpeed * (1.0 - (h - y) / edgeThreshold)
        } else {
            velocity = 0
        }
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        velocity = 0
    }

    private func tick() {
        guard velocity != 0,
              let hostView,
              let scrollView = hostView.enclosingScrollView else { return }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        origin.y += velocity
        let docHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, docHeight - scrollView.contentSize.height)
        origin.y = min(max(origin.y, 0), maxY)
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}
