import Foundation
import SwiftUI

@MainActor
final class ExportOptionsViewModel: ObservableObject {
    let request: ExportRequest
    let aspectRatio: CGFloat
    let origW: Int
    let origH: Int

    @Published var format: ExportFormat
    @Published var jpegQuality: JPEGQualityPreset
    @Published var pngOptimize: Bool
    @Published var pngLevel: PNGOptimizationLevel
    @Published var resizeEnabled: Bool
    @Published var widthText: String
    @Published var heightText: String
    @Published var dpi: ExportDPI
    @Published var tiffCompression: TIFFCompression
    @Published var pdfCompression: PDFImageCompression
    @Published var webpQuality: WebPQualityPreset

    private var isProgrammatic = false

    init(request: ExportRequest) {
        self.request = request
        let w = Int(request.originalSize.width)
        let h = Int(request.originalSize.height)
        self.origW = w
        self.origH = h
        self.aspectRatio = w > 0 && h > 0 ? request.originalSize.width / request.originalSize.height : 1.0

        let ud = UserDefaults.standard
        let fmtRaw = ud.string(forKey: ExportSettings.StorageKey.format) ?? ExportFormat.png.rawValue
        self.format = ExportFormat(rawValue: fmtRaw) ?? .png

        let qualityRaw = ud.integer(forKey: ExportSettings.StorageKey.jpegQuality)
        self.jpegQuality = JPEGQualityPreset(rawValue: qualityRaw == 0 ? 98 : qualityRaw) ?? .high98

        self.pngOptimize = ud.bool(forKey: ExportSettings.StorageKey.pngOptimize)

        let levelRaw = ud.integer(forKey: ExportSettings.StorageKey.pngLevel)
        self.pngLevel = PNGOptimizationLevel(rawValue: levelRaw) ?? .fast

        self.resizeEnabled = ud.bool(forKey: ExportSettings.StorageKey.resizeEnabled)

        let storedW = ud.integer(forKey: ExportSettings.StorageKey.resizeWidth)
        let storedH = ud.integer(forKey: ExportSettings.StorageKey.resizeHeight)
        // 保存済みサイズが現在の画像を超える場合は画像実寸にリセット（アップスケールを防ぐ）
        let storedFits = w > 0 && h > 0 && storedW > 0 && storedH > 0 && storedW <= w && storedH <= h
        self.widthText = storedFits ? String(storedW) : (w > 0 ? String(w) : "")
        self.heightText = storedFits ? String(storedH) : (h > 0 ? String(h) : "")

        let dpiRaw = ud.integer(forKey: ExportSettings.StorageKey.dpi)
        self.dpi = ExportDPI(rawValue: dpiRaw == 0 ? 300 : dpiRaw) ?? .dpi300

        let tiffRaw = ud.string(forKey: ExportSettings.StorageKey.tiffCompression) ?? TIFFCompression.lzw.rawValue
        self.tiffCompression = TIFFCompression(rawValue: tiffRaw) ?? .lzw

        let pdfRaw = ud.string(forKey: ExportSettings.StorageKey.pdfCompression) ?? PDFImageCompression.lossless.rawValue
        self.pdfCompression = PDFImageCompression(rawValue: pdfRaw) ?? .lossless

        let webpRaw = ud.integer(forKey: ExportSettings.StorageKey.webpQuality)
        self.webpQuality = WebPQualityPreset(rawValue: webpRaw == 0 ? 75 : webpRaw) ?? .mid75
    }

    var widthInt: Int? { Int(widthText) }
    var heightInt: Int? { Int(heightText) }

    var isUpscale: Bool {
        origW > 0 && origH > 0 && ((widthInt ?? 0) > origW || (heightInt ?? 0) > origH)
    }

    var isResizeValid: Bool {
        guard resizeEnabled else { return true }
        guard let w = widthInt, let h = heightInt else { return false }
        return w > 0 && h > 0 && !isUpscale
    }

    var isValid: Bool { isResizeValid }

    var currentSettings: ExportSettings {
        ExportSettings(
            format: format,
            jpegQuality: jpegQuality,
            pngOptimize: pngOptimize,
            pngLevel: pngLevel,
            resizeEnabled: resizeEnabled,
            resizeWidth: widthInt ?? origW,
            resizeHeight: heightInt ?? origH,
            dpi: dpi,
            tiffCompression: tiffCompression,
            pdfCompression: pdfCompression,
            webpQuality: webpQuality
        )
    }

    func userDidChangeWidth() {
        guard !isProgrammatic, let w = widthInt, w > 0 else { return }
        let h = Int((CGFloat(w) / aspectRatio).rounded())
        isProgrammatic = true
        defer { isProgrammatic = false }
        heightText = String(h)
    }

    func userDidChangeHeight() {
        guard !isProgrammatic, let h = heightInt, h > 0 else { return }
        let w = Int((CGFloat(h) * aspectRatio).rounded())
        isProgrammatic = true
        defer { isProgrammatic = false }
        widthText = String(w)
    }

    func saveSettings() {
        let ud = UserDefaults.standard
        ud.set(format.rawValue, forKey: ExportSettings.StorageKey.format)
        ud.set(jpegQuality.rawValue, forKey: ExportSettings.StorageKey.jpegQuality)
        ud.set(pngOptimize, forKey: ExportSettings.StorageKey.pngOptimize)
        ud.set(pngLevel.rawValue, forKey: ExportSettings.StorageKey.pngLevel)
        ud.set(resizeEnabled, forKey: ExportSettings.StorageKey.resizeEnabled)
        ud.set(widthInt ?? origW, forKey: ExportSettings.StorageKey.resizeWidth)
        ud.set(heightInt ?? origH, forKey: ExportSettings.StorageKey.resizeHeight)
        ud.set(dpi.rawValue, forKey: ExportSettings.StorageKey.dpi)
        ud.set(tiffCompression.rawValue, forKey: ExportSettings.StorageKey.tiffCompression)
        ud.set(pdfCompression.rawValue, forKey: ExportSettings.StorageKey.pdfCompression)
        ud.set(webpQuality.rawValue, forKey: ExportSettings.StorageKey.webpQuality)
    }
}
