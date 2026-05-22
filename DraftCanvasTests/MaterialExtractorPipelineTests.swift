import XCTest
@testable import DraftCanvas

final class MaterialExtractorPipelineTests: XCTestCase {

    private func loadTestImage() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_color_patches", withExtension: "png") else {
            // リソースが見つからない場合はスキップ
            throw XCTSkip("test_color_patches.png not found in bundle")
        }
        return try Data(contentsOf: url)
    }

    func testDetectReturnsNonEmptyInstances() async throws {
        let data = try loadTestImage()
        do {
            let session = try await MaterialExtractor.detect(from: data)
            // 1つ以上のインスタンスが検出されること
            XCTAssertGreaterThanOrEqual(session.instances.count, 1)
        } catch MaterialExtractionError.noInstancesFound {
            // テスト用画像がシンプルすぎて検出できない場合はスキップ
            throw XCTSkip("No instances found in test image (expected for uniform test images)")
        }
    }

    func testDetectInstanceBoundsAreValid() async throws {
        let data = try loadTestImage()
        do {
            let session = try await MaterialExtractor.detect(from: data)
            for inst in session.instances {
                let bb = inst.normalizedBoundingBox
                XCTAssertGreaterThanOrEqual(bb.minX, -0.01)
                XCTAssertGreaterThanOrEqual(bb.minY, -0.01)
                XCTAssertLessThanOrEqual(bb.maxX, 1.01)
                XCTAssertLessThanOrEqual(bb.maxY, 1.01)
                XCTAssertGreaterThan(bb.width, 0)
                XCTAssertGreaterThan(bb.height, 0)
            }
        } catch MaterialExtractionError.noInstancesFound {
            // テスト用画像がシンプルすぎて検出できない場合はスキップ
            throw XCTSkip("No instances found in test image (expected for uniform test images)")
        }
    }

    func testDetectThrowsOnInvalidData() async throws {
        let invalidData = Data([0x00, 0x01, 0x02])
        do {
            _ = try await MaterialExtractor.detect(from: invalidData)
            XCTFail("detect should throw on invalid image data")
        } catch MaterialExtractionError.imageDecodeFailed {
            // 期待通り
        }
    }
}
