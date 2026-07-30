import XCTest
import AppKit
@testable import DraftCanvas

#if DEBUG
@MainActor
final class CanvasMetricsTests: XCTestCase {
    let testImageURL = URL(fileURLWithPath: "/Users/mbp16-max/app-develop/draftcanvas/_docs/test_14.png")

    override func setUp() async throws {
        CanvasMetrics.reset()
    }

    func testReset_clearsCounters() {
        CanvasMetrics.imageLoadCount = 5
        CanvasMetrics.imageLoadBytesEstimate = 1_000_000
        CanvasMetrics.reset()
        XCTAssertEqual(CanvasMetrics.imageLoadCount, 0)
        XCTAssertEqual(CanvasMetrics.imageLoadBytesEstimate, 0)
    }

    func testResidentMemoryMB_isPositive() {
        XCTAssertGreaterThan(CanvasMetrics.residentMemoryMB, 0,
            "resident メモリは正の値であるべき")
    }

    func testImageLoad_incrementsCountAndBytes() throws {
        guard let img = NSImage(contentsOf: testImageURL) else {
            throw XCTSkip("test_14.png が見つかりません: \(testImageURL.path)")
        }

        CanvasMetrics.imageLoadCount += 1
        if let rep = img.representations.first(where: { $0 is NSBitmapImageRep }) ?? img.representations.first {
            CanvasMetrics.imageLoadBytesEstimate += rep.pixelsWide * rep.pixelsHigh * 4
        }

        XCTAssertEqual(CanvasMetrics.imageLoadCount, 1, "ロード1回でカウント1")
        XCTAssertGreaterThan(CanvasMetrics.imageLoadBytesEstimate, 0, "推定バイト数は正")
    }

    func testLogSummary_containsExpectedFields() throws {
        guard NSImage(contentsOf: testImageURL) != nil else {
            throw XCTSkip("test_14.png が見つかりません")
        }
        CanvasMetrics.imageLoadCount = 3
        CanvasMetrics.imageLoadBytesEstimate = 4_194_304 // 4MB

        let summary = CanvasMetrics.logSummary(tag: "test")
        XCTAssertTrue(summary.contains("[CanvasMetrics:test]"), "タグ含む: \(summary)")
        XCTAssertTrue(summary.contains("loads=3"), "ロード数含む: \(summary)")
        XCTAssertTrue(summary.contains("estimatedMB=4"), "推定MB含む: \(summary)")
        XCTAssertTrue(summary.contains("residentMB="), "residentMB含む: \(summary)")
    }

    func testImagePixelSize_matchesExpected() throws {
        guard let img = NSImage(contentsOf: testImageURL) else {
            throw XCTSkip("test_14.png が見つかりません")
        }
        let ratio = img.pixelAspectRatio
        XCTAssertNotNil(ratio, "pixelAspectRatio が取得できる")
        XCTAssertGreaterThan(ratio ?? 0, 0, "アスペクト比は正")

        let rep = img.representations.first(where: { $0 is NSBitmapImageRep }) ?? img.representations.first
        XCTAssertNotNil(rep, "ビットマップ表現が存在する")
        XCTAssertGreaterThan(rep?.pixelsWide ?? 0, 0, "幅 > 0")
        XCTAssertGreaterThan(rep?.pixelsHigh ?? 0, 0, "高さ > 0")
    }

    func testPromptPanelHeightClampsInvalidRestoredGeometryValues() {
        let expandedHeight = PromptPanelLayout.clampedHeight(
            promptTextHeight: .nan,
            maxPromptHeight: .infinity,
            isEmptyIdle: false,
            isCollapsed: false
        )

        XCTAssertEqual(expandedHeight, 76)

        let emptyIdleHeight = PromptPanelLayout.clampedHeight(
            promptTextHeight: -.infinity,
            maxPromptHeight: -.infinity,
            isEmptyIdle: true,
            isCollapsed: false
        )

        XCTAssertEqual(emptyIdleHeight, 28)
    }

    func testZoomableImageMinimumMagnificationClampsToFloor() {
        // フィット倍率が等倍付近なら下限は固定値 0.05
        XCTAssertEqual(ZoomableImageView.minimumMagnification(forFit: 1.0), 0.05, accuracy: 0.0001)
        // 巨大画像でフィット倍率自体が下限を割る場合はさらに引けるようにする
        XCTAssertEqual(ZoomableImageView.minimumMagnification(forFit: 0.02), 0.01, accuracy: 0.0001)
        // 不正値はレイアウト未確定時に届くため既定の下限へ落とす
        XCTAssertEqual(ZoomableImageView.minimumMagnification(forFit: 0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(ZoomableImageView.minimumMagnification(forFit: -1), 0.05, accuracy: 0.0001)
    }

    func testZoomableImageLogicalSizeUsesPixelDimensions() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 640,
            pixelsHigh: 480,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        // NSImage.size が pt 単位で縮んでいても 100% はピクセル数基準にする
        let image = NSImage(size: CGSize(width: 320, height: 240))
        image.addRepresentation(rep)

        XCTAssertEqual(ZoomableImageView.logicalSize(of: image), CGSize(width: 640, height: 480))
    }

    func testZoomableImageLogicalSizeFallsBackToImageSize() {
        // representations を持たない画像では size をそのまま使う
        let image = NSImage(size: CGSize(width: 200, height: 100))

        XCTAssertEqual(ZoomableImageView.logicalSize(of: image), CGSize(width: 200, height: 100))
    }
}
#endif
