import Foundation

enum WebPEncoder {
    static func encode(pngData: Data, quality: Int) async throws -> Data {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let inputURL = tmp.appendingPathComponent("webp-in-\(UUID().uuidString).png")
        let outputURL = tmp.appendingPathComponent("webp-out-\(UUID().uuidString).webp")

        defer {
            try? fm.removeItem(at: inputURL)
            try? fm.removeItem(at: outputURL)
        }

        try pngData.write(to: inputURL, options: .atomic)

        _ = try await BinaryRunner.run(
            binary: "cwebp",
            arguments: [
                "-q", String(quality),
                "-metadata", "none",
                inputURL.path,
                "-o", outputURL.path
            ],
            timeout: 60
        )

        guard fm.fileExists(atPath: outputURL.path) else {
            throw ExportError.encodeFailed
        }

        return try Data(contentsOf: outputURL)
    }
}
