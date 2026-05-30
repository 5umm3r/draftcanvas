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
            do {
                let tmpDir = FileManager.default.temporaryDirectory
                let losslessPath = tmpDir.appendingPathComponent("export-lossless-\(UUID().uuidString).png")
                try output.write(to: losslessPath, options: .atomic)
                defer { try? FileManager.default.removeItem(at: losslessPath) }

                let isMax = settings.pngLevel == .max
                let oxiLevel = isMax ? "4" : "2"
                let oxiStrip = isMax ? "all" : "safe"
                let oxiTimeout: TimeInterval = isMax ? 300 : 120

                var losslessArgs = ["-o", oxiLevel, "--strip", oxiStrip]
                if isMax { losslessArgs += ["--interlace", "0"] }
                losslessArgs.append(losslessPath.path)

                _ = try await BinaryRunner.run(
                    binary: "oxipng",
                    arguments: losslessArgs,
                    timeout: oxiTimeout
                )

                if settings.pngLevel.isLossy {
                    // pngquant（ロッシー）→ oxipng（ロスレス）の順で別パスを生成し、小さい方を採用
                    let lossyBase = tmpDir.appendingPathComponent("export-lossy-\(UUID().uuidString).png")
                    try output.write(to: lossyBase, options: .atomic)
                    defer { try? FileManager.default.removeItem(at: lossyBase) }

                    let quantOut = tmpDir.appendingPathComponent("quant-\(UUID().uuidString).png")
                    defer { try? FileManager.default.removeItem(at: quantOut) }

                    _ = try await BinaryRunner.run(
                        binary: "pngquant",
                        arguments: [
                            "--quality", "65-80",
                            "--skip-if-larger",
                            "--output", quantOut.path,
                            "--force",
                            lossyBase.path
                        ],
                        timeout: 60
                    )

                    if FileManager.default.fileExists(atPath: quantOut.path) {
                        _ = try FileManager.default.replaceItemAt(lossyBase, withItemAt: quantOut)
                        var lossyArgs = ["-o", oxiLevel, "--strip", oxiStrip]
                        if isMax { lossyArgs += ["--interlace", "0"] }
                        lossyArgs.append(lossyBase.path)

                        _ = try await BinaryRunner.run(
                            binary: "oxipng",
                            arguments: lossyArgs,
                            timeout: oxiTimeout
                        )
                        let losslessSize = (try? FileManager.default.attributesOfItem(atPath: losslessPath.path)[.size] as? Int) ?? Int.max
                        let lossySize = (try? FileManager.default.attributesOfItem(atPath: lossyBase.path)[.size] as? Int) ?? Int.max
                        if lossySize < losslessSize {
                            output = try Data(contentsOf: lossyBase)
                        } else {
                            output = try Data(contentsOf: losslessPath)
                        }
                    } else {
                        output = try Data(contentsOf: losslessPath)
                    }
                } else {
                    output = try Data(contentsOf: losslessPath)
                }
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
