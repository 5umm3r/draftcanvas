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
        case .webp:
            output = try await WebPEncoder.encode(
                pngData: processedPNG,
                quality: settings.webpQuality.rawValue
            )
        }

        if settings.format == .png && settings.pngOptimize {
            let tmpDir = FileManager.default.temporaryDirectory
            let losslessPath = tmpDir.appendingPathComponent("export-lossless-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: losslessPath) }

            let isMax = settings.pngLevel == .max
            let oxiLevel = isMax ? "4" : "2"
            let oxiStrip = isMax ? "all" : "safe"
            let oxiTimeout: TimeInterval = isMax ? 300 : 120

            func oxipngArgs(for path: String) -> [String] {
                var args = ["-o", oxiLevel, "--strip", oxiStrip]
                if isMax { args += ["--interlace", "0"] }
                args.append(path)
                return args
            }

            // ロスレス（oxipng）: 成功すれば output に反映。失敗しても未圧縮で続行（致命的でない）
            do {
                try output.write(to: losslessPath, options: .atomic)
                _ = try await BinaryRunner.run(
                    binary: "oxipng",
                    arguments: oxipngArgs(for: losslessPath.path),
                    timeout: oxiTimeout
                )
                output = try Data(contentsOf: losslessPath)
            } catch {
                logger("PNG最適化（ロスレス）失敗、未圧縮で保存: \(error.localizedDescription)")
            }

            // ロッシー（pngquant → oxipng）: 失敗してもロスレス結果を保持し、小さい方を採用
            if settings.pngLevel.isLossy {
                do {
                    let lossyBase = tmpDir.appendingPathComponent("export-lossy-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at: lossyBase) }
                    let quantOut = tmpDir.appendingPathComponent("quant-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at: quantOut) }

                    try output.write(to: lossyBase, options: .atomic)

                    // 終了コード 98（skip-if-larger）/ 99（品質下限未達）は正常スキップ扱い
                    _ = try await BinaryRunner.run(
                        binary: "pngquant",
                        arguments: [
                            "--quality", "65-80",
                            "--skip-if-larger",
                            "--output", quantOut.path,
                            "--force",
                            lossyBase.path
                        ],
                        timeout: 60,
                        allowedExitCodes: [0, 98, 99]
                    )

                    if FileManager.default.fileExists(atPath: quantOut.path) {
                        _ = try FileManager.default.replaceItemAt(lossyBase, withItemAt: quantOut)
                        _ = try await BinaryRunner.run(
                            binary: "oxipng",
                            arguments: oxipngArgs(for: lossyBase.path),
                            timeout: oxiTimeout
                        )
                        let lossySize = (try? FileManager.default.attributesOfItem(atPath: lossyBase.path)[.size] as? Int) ?? Int.max
                        if lossySize < output.count {
                            output = try Data(contentsOf: lossyBase)
                        }
                    }
                    // quantOut 未生成 = pngquant がスキップ → ロスレス結果（output）を保持
                } catch {
                    logger("PNG最適化（ロッシー）スキップ、ロスレス結果を保持: \(error.localizedDescription)")
                }
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
