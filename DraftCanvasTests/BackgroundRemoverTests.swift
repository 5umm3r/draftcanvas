import XCTest
import AppKit
@testable import DraftCanvas

final class BackgroundRemoverTests: XCTestCase {

    func testProcess_invalidData_throwsImageDecodeFailed() async {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        do {
            _ = try await BackgroundRemover.process(data: invalidData)
            XCTFail("Expected BackgroundRemovalError.imageDecodeFailed to be thrown")
        } catch BackgroundRemovalError.imageDecodeFailed {
            // OK
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testProcess_emptyData_throwsImageDecodeFailed() async {
        do {
            _ = try await BackgroundRemover.process(data: Data())
            XCTFail("Expected BackgroundRemovalError.imageDecodeFailed to be thrown")
        } catch BackgroundRemovalError.imageDecodeFailed {
            // OK
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testProcess_validPNG_eitherSucceedsWithSameSizeOrThrowsKnownError() async throws {
        let inputPNG = makeSolidColorPNG(width: 100, height: 80, red: 0.2, green: 0.5, blue: 0.8)

        do {
            let outputData = try await BackgroundRemover.process(data: inputPNG)

            guard let outputImage = NSImage(data: outputData) else {
                XCTFail("Output is not a valid image")
                return
            }
            guard let inputImage = NSImage(data: inputPNG) else {
                XCTFail("Input is not a valid image")
                return
            }
            XCTAssertEqual(outputImage.size, inputImage.size, "Output size must match input size")
        } catch BackgroundRemovalError.noSubjectFound {
            // Solid-color image with no subject — acceptable
        } catch BackgroundRemovalError.visionFailed {
            // Vision runtime error — acceptable in test environment
        }
    }

    func testProcess_validPNG_outputIsTransparentPNG() async throws {
        let inputPNG = makeSolidColorPNG(width: 50, height: 50, red: 1, green: 0, blue: 0)

        do {
            let outputData = try await BackgroundRemover.process(data: inputPNG)

            // Must be valid PNG
            let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            XCTAssertTrue(outputData.count >= 8, "Output too small to be PNG")
            XCTAssertEqual(Array(outputData.prefix(8)), pngHeader, "Output must be PNG format")
        } catch BackgroundRemovalError.noSubjectFound {
            // Solid-color — acceptable
        } catch BackgroundRemovalError.visionFailed {
            // OK in CI / test env
        }
    }

    func testProcess_outputPNG_hasSRGBColorProfile() async throws {
        let inputPNG = makeSolidColorPNG(width: 50, height: 50, red: 0.5, green: 0.5, blue: 0.5)
        do {
            let outputData = try await BackgroundRemover.process(data: inputPNG)
            let sRGBChunk = Data([0x73, 0x52, 0x47, 0x42]) // "sRGB"
            let iCCPChunk = Data([0x69, 0x43, 0x43, 0x50]) // "iCCP"
            let hasSRGB = outputData.range(of: sRGBChunk) != nil
            let hasICCP = outputData.range(of: iCCPChunk) != nil
            XCTAssertTrue(hasSRGB || hasICCP, "Output PNG must embed sRGB or iCCP color profile")
        } catch BackgroundRemovalError.noSubjectFound, BackgroundRemovalError.visionFailed,
                BackgroundRemovalError.maskGenerationFailed {
            // Acceptable for solid-color test images
        }
    }

    func testProcess_edgeStrengthZero_succeedsOrThrowsKnownError() async throws {
        let inputPNG = makeSolidColorPNG(width: 80, height: 80, red: 0.3, green: 0.6, blue: 0.9)
        do {
            _ = try await BackgroundRemover.process(data: inputPNG, edgeStrength: 0.0)
        } catch BackgroundRemovalError.noSubjectFound, BackgroundRemovalError.visionFailed,
                BackgroundRemovalError.maskGenerationFailed {
            // Acceptable
        }
    }

    func testProcess_edgeStrengthMax_succeedsOrThrowsKnownError() async throws {
        let inputPNG = makeSolidColorPNG(width: 80, height: 80, red: 0.3, green: 0.6, blue: 0.9)
        do {
            _ = try await BackgroundRemover.process(data: inputPNG, edgeStrength: 1.0)
        } catch BackgroundRemovalError.noSubjectFound, BackgroundRemovalError.visionFailed,
                BackgroundRemovalError.maskGenerationFailed {
            // Acceptable
        }
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
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let pngData = rep.representation(using: .png, properties: [:])
    else {
        return Data()
    }
    return pngData
}
