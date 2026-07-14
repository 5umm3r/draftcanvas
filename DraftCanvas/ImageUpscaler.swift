import Foundation

enum UpscaleModel: String, CaseIterable, Identifiable {
    case general = "realesrgan-x4plus"
    case anime = "realesrgan-x4plus-anime"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return String(localized: "汎用")
        case .anime: return String(localized: "イラスト")
        }
    }
}

/// realesrgan-ncnn-vulkan (同梱バイナリ) によるローカル 4 倍アップスケール
enum ImageUpscaler {
    enum Failure: Error, LocalizedError {
        case modelsDirectoryNotFound
        case outputNotProduced

        var errorDescription: String? {
            switch self {
            case .modelsDirectoryNotFound:
                return String(localized: "アップスケールモデルが見つかりません")
            case .outputNotProduced:
                return String(localized: "アップスケール結果の出力に失敗しました")
            }
        }
    }

    static func upscale(fileURL: URL, model: UpscaleModel) async throws -> Data {
        guard let modelsDir = Bundle.main.url(forResource: "models", withExtension: nil) else {
            throw Failure.modelsDirectoryNotFound
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upscale-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // GPU 性能によっては大判画像で数分かかるためタイムアウトは長めに取る
        _ = try await BinaryRunner.run(
            binary: "realesrgan-ncnn-vulkan",
            arguments: [
                "-i", fileURL.path,
                "-o", outputURL.path,
                "-n", model.rawValue,
                "-m", modelsDir.path
            ],
            timeout: 600
        )
        guard let data = try? Data(contentsOf: outputURL) else {
            throw Failure.outputNotProduced
        }
        return data
    }
}

struct UpscalePreviewPayload: Identifiable {
    let id = UUID()
    let originalItem: ProjectItem
    let originalImageData: Data
    let upscaledImageData: Data
    let model: UpscaleModel
    let jobLogs: [String]
}

enum UpscaleApplyMode {
    case overwrite
    case addAsNew
    case discard
}
