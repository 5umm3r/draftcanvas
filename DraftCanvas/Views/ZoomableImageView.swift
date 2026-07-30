import SwiftUI
import AppKit

/// プレビュー画像を任意倍率で拡大縮小できるスクロールビュー。
/// 倍率 1.0 は画像のピクセル数と同じ論理サイズ（UpscalePreviewSheet の 100% と同じ定義）。
/// ピンチ・スマートマグニファイ・慣性パンは NSScrollView の標準実装をそのまま使う。
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    /// 現在倍率。外部から変更するとビューポート中心を保ったままズームする。
    @Binding var magnification: CGFloat
    /// 画像全体が収まる倍率。レイアウト確定時とサイズ変更時に書き戻される。
    @Binding var fitMagnification: CGFloat
    /// true のとき nearest neighbor で描画し、ピクセル境界をシャープに見せる。
    let usesPixelInterpolation: Bool
    /// 画像の外側（スクロールビュー内の余白）がクリックされたときに呼ばれる。
    let onBackgroundClick: () -> Void

    static let maxMagnification: CGFloat = 8.0

    /// フィット倍率よりさらに引けるよう下限に余裕を持たせる。
    static func minimumMagnification(forFit fit: CGFloat) -> CGFloat {
        guard fit > 0 else { return 0.05 }
        return min(0.05, fit * 0.5)
    }

    /// 画像のピクセル数を論理サイズとして扱う（Retina では画面上 2 倍の密度で描かれる）。
    static func logicalSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if image.size.width > 0, image.size.height > 0 {
            return image.size
        }
        return CGSize(width: 1024, height: 1024)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ZoomableScrollView {
        let scrollView = ZoomableScrollView()
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = Self.maxMagnification
        scrollView.minMagnification = 0.05
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        // 画像がビューポートより小さいときに中央寄せするための差し替え
        let clipView = CenteringClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let documentView = ZoomableImageDocumentView()
        documentView.image = image
        documentView.usesPixelInterpolation = usesPixelInterpolation
        documentView.frame = CGRect(origin: .zero, size: Self.logicalSize(of: image))
        scrollView.documentView = documentView
        scrollView.onBackgroundClick = onBackgroundClick

        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: ZoomableScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.onBackgroundClick = onBackgroundClick
        guard let documentView = scrollView.documentView as? ZoomableImageDocumentView else { return }

        if documentView.image !== image {
            documentView.image = image
            documentView.frame = CGRect(origin: .zero, size: Self.logicalSize(of: image))
            documentView.needsDisplay = true
            context.coordinator.resetForNewImage()
        }

        if documentView.usesPixelInterpolation != usesPixelInterpolation {
            documentView.usesPixelInterpolation = usesPixelInterpolation
            documentView.needsDisplay = true
        }

        context.coordinator.applyExternalMagnification(magnification)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var parent: ZoomableImageView
        private weak var scrollView: ZoomableScrollView?
        private var hasAppliedInitialFit = false

        init(_ parent: ZoomableImageView) {
            self.parent = parent
        }

        func attach(to scrollView: ZoomableScrollView) {
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true

            // ピンチ・スマートマグニファイ・ホイールズームは bounds 変化として届く
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            // 初回レイアウトとウィンドウリサイズの両方でフィット倍率を取り直す
            scrollView.onLayout = { [weak self] in
                self?.recalculateFit()
            }
        }

        // selector 版の通知登録は observer の解放時に自動で外れるため detach は持たない

        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            syncMagnificationFromScrollView()
        }

        func resetForNewImage() {
            hasAppliedInitialFit = false
            recalculateFit()
        }

        /// AppKit 側のズーム結果を SwiftUI に書き戻す。
        private func syncMagnificationFromScrollView() {
            guard let scrollView else { return }
            let current = scrollView.magnification
            guard abs(current - parent.magnification) > 0.0001 else { return }
            let binding = parent.$magnification
            DispatchQueue.main.async { binding.wrappedValue = current }
        }

        /// SwiftUI 側の倍率変更を AppKit に反映する。差分がなければ何もしない。
        func applyExternalMagnification(_ value: CGFloat) {
            guard let scrollView, value > 0 else { return }
            let clamped = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
            guard abs(scrollView.magnification - clamped) > 0.0001 else { return }
            let visible = scrollView.contentView.bounds
            let center = NSPoint(x: visible.midX, y: visible.midY)
            scrollView.setMagnification(clamped, centeredAt: center)
        }

        private func recalculateFit() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            // clipView の frame は倍率の影響を受けないため、そのままビューポートとして使える
            let viewport = scrollView.contentView.frame.size
            let content = documentView.frame.size
            guard viewport.width > 1, viewport.height > 1, content.width > 0, content.height > 0 else { return }

            let fit = min(viewport.width / content.width, viewport.height / content.height)
            let clampedFit = min(fit, ZoomableImageView.maxMagnification)
            scrollView.minMagnification = ZoomableImageView.minimumMagnification(forFit: clampedFit)

            if abs(clampedFit - parent.fitMagnification) > 0.0001 {
                let binding = parent.$fitMagnification
                DispatchQueue.main.async { binding.wrappedValue = clampedFit }
            }

            guard !hasAppliedInitialFit else { return }
            hasAppliedInitialFit = true
            scrollView.magnification = clampedFit
            let binding = parent.$magnification
            DispatchQueue.main.async { binding.wrappedValue = clampedFit }
        }
    }
}

// MARK: - AppKit views

/// レイアウト完了を通知する NSScrollView。フィット倍率の再計算タイミングに使う。
final class ZoomableScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var onBackgroundClick: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    /// スクロールビューはビューポート全体を占めるため、画像の外側をクリックしたときは
    /// オーバーレイの背景タップと同じ扱いにする（画像本体のクリックは従来どおり閉じない）。
    override func mouseDown(with event: NSEvent) {
        guard let documentView else {
            super.mouseDown(with: event)
            return
        }
        let point = documentView.convert(event.locationInWindow, from: nil)
        if documentView.bounds.contains(point) {
            super.mouseDown(with: event)
        } else {
            onBackgroundClick?()
        }
    }
}

/// ドキュメントがビューポートより小さいとき中央に寄せる NSClipView。
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let documentFrame = documentView.frame

        if rect.width > documentFrame.width {
            rect.origin.x = (documentFrame.width - rect.width) / 2
        }
        if rect.height > documentFrame.height {
            rect.origin.y = (documentFrame.height - rect.height) / 2
        }
        return rect
    }
}

/// 画像 1 枚を論理ピクセルサイズで描画するドキュメントビュー。
/// isFlipped は実装しない。NSImage.draw(in:) は flipped コンテキストを自前で補正するため、
/// 左上原点にすると上下反転して描画されてしまう。
/// 初期表示はフィット倍率かつ CenteringClipView で中央寄せされるため、下原点でも支障はない。
final class ZoomableImageDocumentView: NSView {
    var image: NSImage?
    var usesPixelInterpolation = false

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current else { return }
        context.imageInterpolation = usesPixelInterpolation ? .none : .high
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
