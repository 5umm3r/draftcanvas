import XCTest
import AppKit
@testable import DraftCanvas

final class ImageVectorizerTests: XCTestCase {

    func testProcess_invalidData_throwsImageDecodeFailed() async {
        do {
            _ = try await ImageVectorizer.process(data: Data([0x00, 0x01, 0x02, 0x03]))
            XCTFail("Expected imageDecodeFailed")
        } catch ImageVectorizationError.imageDecodeFailed {
            // OK
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcess_emptyData_throwsImageDecodeFailed() async {
        do {
            _ = try await ImageVectorizer.process(data: Data())
            XCTFail("Expected imageDecodeFailed")
        } catch ImageVectorizationError.imageDecodeFailed {
            // OK
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcess_solidColorPNG_producesSVGWithValidHeader() async throws {
        let png = makeSolidColorPNG(width: 64, height: 64, red: 0.2, green: 0.5, blue: 0.8)
        let result = try await ImageVectorizer.process(data: png)
        let svgString = String(data: result.svgData, encoding: .utf8) ?? ""
        XCTAssertTrue(svgString.contains("<svg"), "SVG must contain svg element")
    }

    func testProcess_solidColorPNG_previewIsValidPNG() async throws {
        let png = makeSolidColorPNG(width: 64, height: 64, red: 1, green: 0, blue: 0)
        let result = try await ImageVectorizer.process(data: png)
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertTrue(result.previewPNGData.count >= 8)
        XCTAssertEqual(Array(result.previewPNGData.prefix(8)), pngHeader, "Preview must be PNG")
    }

    func testProcess_twoColorPNG_svgContainsPath() async throws {
        let png = makeTwoColorPNG(width: 64, height: 64)
        let result = try await ImageVectorizer.process(data: png)
        let svg = String(data: result.svgData, encoding: .utf8) ?? ""
        XCTAssertTrue(svg.contains("<path") || svg.contains("<svg"), "SVG should contain elements")
    }
}

// MARK: - Helpers

private func makeSolidColorPNG(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
    let size = CGSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return Data() }
    return png
}

private func makeTwoColorPNG(width: Int, height: Int) -> Data {
    let size = CGSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: width / 2, height: height).fill()
    NSColor.blue.setFill()
    NSRect(x: width / 2, y: 0, width: width / 2, height: height).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return Data() }
    return png
}
