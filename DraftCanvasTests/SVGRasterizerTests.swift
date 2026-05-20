import XCTest
import AppKit
@testable import DraftCanvas

final class SVGRasterizerTests: XCTestCase {

    func testRasterize_validSVG_returnsPNG() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
          <rect width="64" height="64" fill="#FF0000"/>
        </svg>
        """.data(using: .utf8)!
        let result = SVGRasterizer.rasterize(svgData: svg)
        XCTAssertNotNil(result, "Valid SVG should produce PNG")
        if let data = result {
            let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            XCTAssertEqual(Array(data.prefix(8)), pngHeader, "Result must be PNG format")
        }
    }

    func testRasterize_invalidData_returnsNil() {
        let result = SVGRasterizer.rasterize(svgData: Data([0x00, 0x01, 0x02, 0x03]))
        XCTAssertNil(result, "Invalid data should return nil")
    }

    func testRasterize_emptyData_returnsNil() {
        let result = SVGRasterizer.rasterize(svgData: Data())
        XCTAssertNil(result, "Empty data should return nil")
    }
}
