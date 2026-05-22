import XCTest
import CoreGraphics
@testable import DraftCanvas

#if DEBUG
@MainActor
final class CropEditorMathTests: XCTestCase {

    // MARK: - largestInscribed

    func testLargestInscribed_squareRatioInSquareRect() {
        // ratio 1:1 inside a 100x100 rect → fills completely
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = CropEditorSheet.largestInscribed(ratio: 1.0, in: rect)
        XCTAssertEqual(result.width, 100, accuracy: 0.001)
        XCTAssertEqual(result.height, 100, accuracy: 0.001)
        XCTAssertEqual(result.midX, 50, accuracy: 0.001)
        XCTAssertEqual(result.midY, 50, accuracy: 0.001)
    }

    func testLargestInscribed_wideRatioInTallRect() {
        // ratio 2:1 (landscape) inside a 100x200 rect → constrained by width
        let rect = CGRect(x: 0, y: 0, width: 100, height: 200)
        let result = CropEditorSheet.largestInscribed(ratio: 2.0, in: rect)
        XCTAssertEqual(result.width, 100, accuracy: 0.001)
        XCTAssertEqual(result.height, 50, accuracy: 0.001)
        XCTAssertEqual(result.midX, 50, accuracy: 0.001)
        XCTAssertEqual(result.midY, 100, accuracy: 0.001)
    }

    func testLargestInscribed_tallRatioInWideRect() {
        // ratio 1:2 (portrait) inside a 200x100 rect → constrained by height
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let result = CropEditorSheet.largestInscribed(ratio: 0.5, in: rect)
        XCTAssertEqual(result.height, 100, accuracy: 0.001)
        XCTAssertEqual(result.width, 50, accuracy: 0.001)
        XCTAssertEqual(result.midX, 100, accuracy: 0.001)
        XCTAssertEqual(result.midY, 50, accuracy: 0.001)
    }

    func testLargestInscribed_resultIsCenteredInRect() {
        // Result should always be centered within the source rect
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let result = CropEditorSheet.largestInscribed(ratio: 16.0 / 9.0, in: rect)
        XCTAssertEqual(result.midX, rect.midX, accuracy: 0.001)
        XCTAssertEqual(result.midY, rect.midY, accuracy: 0.001)
    }

    func testLargestInscribed_resultFitsInsideRect() {
        // Result must not exceed the bounds of the source rect
        let rect = CGRect(x: 0, y: 0, width: 640, height: 480)
        let result = CropEditorSheet.largestInscribed(ratio: 4.0 / 3.0, in: rect)
        XCTAssertLessThanOrEqual(result.width, rect.width + 0.001)
        XCTAssertLessThanOrEqual(result.height, rect.height + 0.001)
        XCTAssertGreaterThanOrEqual(result.minX, rect.minX - 0.001)
        XCTAssertGreaterThanOrEqual(result.minY, rect.minY - 0.001)
    }

    func testLargestInscribed_16x9InSquare() {
        // 16:9 ratio inside a 900x900 square → width-constrained
        let rect = CGRect(x: 0, y: 0, width: 900, height: 900)
        let result = CropEditorSheet.largestInscribed(ratio: 16.0 / 9.0, in: rect)
        // candidateH = 900 / (16/9) = 506.25 ≤ 900 → width-constrained path
        XCTAssertEqual(result.width, 900, accuracy: 0.001)
        XCTAssertEqual(result.height, 900 / (16.0 / 9.0), accuracy: 0.001)
    }

    // MARK: - pixelSize

    func testPixelSize_fallsBackToImageSize() {
        // NSImage with no representations returns image.size
        let image = NSImage(size: CGSize(width: 320, height: 240))
        let size = CropEditorSheet.pixelSize(of: image)
        XCTAssertEqual(size.width, 320, accuracy: 0.001)
        XCTAssertEqual(size.height, 240, accuracy: 0.001)
    }
}
#endif
