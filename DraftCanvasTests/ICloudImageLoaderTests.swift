import XCTest
@testable import DraftCanvas

final class ICloudImageLoaderTests: XCTestCase {
    func test_loadData_returnsContentsForLocalFile() async throws {
        let loader = ICloudImageLoader()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-test-\(UUID().uuidString).bin")
        let payload = Data([0xCA, 0xFE, 0xBA, 0xBE])
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try await loader.loadData(at: tmp, syncMonitor: nil)
        XCTAssertEqual(result, payload)
    }

    func test_loadData_throwsFileNotFoundForMissingFile() async {
        let loader = ICloudImageLoader()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-test-missing-\(UUID().uuidString)")
        do {
            _ = try await loader.loadData(at: missing, syncMonitor: nil)
            XCTFail("expected throw")
        } catch ICloudImageLoaderError.fileNotFound {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_loadImage_returnsNilForNonImageData() async throws {
        let loader = ICloudImageLoader()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-test-\(UUID().uuidString).bin")
        try Data([0x00, 0x01, 0x02]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let img = try await loader.loadImage(at: tmp, syncMonitor: nil)
        XCTAssertNil(img)
    }
}
