import Foundation

enum ExportPipeline {
    static func run(
        request: ExportRequest,
        settings: ExportSettings,
        destination: URL,
        projectStore: ProjectStore,
        logger: @escaping @Sendable (String) -> Void
    ) async throws {
        let inputPNG = try sourcePNGData(from: request.source, projectStore: projectStore)

        let processedPNG: Data
        if settings.resizeEnabled,
           !(settings.format == .svg && request.hasVectorSVG),
           settings.resizeWidth > 0,
           settings.resizeHeight > 0 {
            processedPNG = try ImageResizer.resize(
                pngData: inputPNG,
                targetWidth: settings.resizeWidth,
                targetHeight: settings.resizeHeight
            )
        } else {
            processedPNG = inputPNG
        }

        var output: Data
        switch settings.format {
        case .png:
            output = processedPNG
        case .jpeg:
            output = try ImageEncoder.jpegData(
                fromPNG: processedPNG,
                quality: settings.jpegQuality.compressionFactor
            )
        case .svg:
            if request.hasVectorSVG,
               case .singleItem(let item) = request.source,
               let svgData = try? Data(contentsOf: item.svgFileURL(in: projectStore.rootDirectory)) {
                output = svgData
            } else {
                output = try ImageEncoder.svgWrapping(pngData: processedPNG)
            }
        case .tiff:
            output = try TIFFEncoder.encode(
                pngData: processedPNG,
                dpi: settings.dpi,
                compression: settings.tiffCompression
            )
        case .pdf:
            output = try PDFEncoder.encode(
                pngData: processedPNG,
                dpi: settings.dpi,
                compression: settings.pdfCompression
            )
        }

        if settings.format == .png && settings.pngOptimize {
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("export-\(UUID().uuidString).png")
                try output.write(to: tmp, options: .atomic)
                defer { try? FileManager.default.removeItem(at: tmp) }

                if settings.pngLevel.isLossy {
                    // pngquant（ロッシー）→ oxipng（ロスレス）の順
                    let quantOut = tmp.deletingLastPathComponent()
                        .appendingPathComponent("quant-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at: quantOut) }
                    _ = try await BinaryRunner.run(
                        binary: "pngquant",
                        arguments: [
                            "--quality", "65-80",
                            "--skip-if-larger",
                            "--output", quantOut.path,
                            "--force",
                            tmp.path
                        ],
                        timeout: 60
                    )
                    if FileManager.default.fileExists(atPath: quantOut.path) {
                        _ = try FileManager.default.replaceItemAt(tmp, withItemAt: quantOut)
                    }
                }

                _ = try await BinaryRunner.run(
                    binary: "oxipng",
                    arguments: ["-o", "2", "--strip", "safe", tmp.path],
                    timeout: 120
                )
                output = try Data(contentsOf: tmp)
            } catch {
                logger("PNG最適化失敗（未圧縮で保存）: \(error.localizedDescription)")
            }
        }

        try output.write(to: destination, options: .atomic)
    }

    private static func sourcePNGData(
        from source: ExportRequest.Source,
        projectStore: ProjectStore
    ) throws -> Data {
        switch source {
        case .singleItem(let item):
            return try Data(contentsOf: projectStore.resolvedFileURL(for: item))
        case .currentJob(let pngData, _):
            return pngData
        case .batchItems:
            fatalError(String(localized: "batchItems は ZipExportPipeline で処理してください"))
        }
    }
}
