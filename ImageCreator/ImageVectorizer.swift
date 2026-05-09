import Vision
import ImageIO

enum ImageVectorizationError: Error, LocalizedError {
    case imageDecodeFailed
    case colorQuantizationFailed
    case contourDetectionFailed(underlying: Error)
    case noContoursFound
    case svgEncodeFailed
    case previewRenderFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:              return "画像ファイルを読み込めませんでした"
        case .colorQuantizationFailed:        return "色の解析に失敗しました"
        case .contourDetectionFailed(let e):  return "輪郭検出に失敗しました: \(e.localizedDescription)"
        case .noContoursFound:                return "画像から輪郭を検出できませんでした"
        case .svgEncodeFailed:                return "SVGの生成に失敗しました"
        case .previewRenderFailed:            return "プレビュー画像の生成に失敗しました"
        }
    }
}

struct VectorizationOptions {
    var maxColors: Int = 8
    var minContourAreaFraction: CGFloat = 0.0005
    var contrastAdjustment: Float = 2.0
    static let `default` = VectorizationOptions()
}

struct VectorizationResult {
    let svgData: Data
    let previewPNGData: Data
}

private struct QuantizedColor {
    let r: UInt8, g: UInt8, b: UInt8, pixelCount: Int
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

private struct PixelRGB {
    var r, g, b, alpha: UInt8
    var isOpaque: Bool { alpha >= 128 }
}

enum ImageVectorizer {

    static func process(data: Data, options: VectorizationOptions = .default) async throws -> VectorizationResult {
        guard let cgImage = makeCGImage(from: data) else {
            throw ImageVectorizationError.imageDecodeFailed
        }
        return try await Task.detached(priority: .userInitiated) {
            try run(cgImage: cgImage, options: options)
        }.value
    }

    // MARK: - Pipeline

    private static func run(cgImage: CGImage, options: VectorizationOptions) throws -> VectorizationResult {
        let w = cgImage.width, h = cgImage.height

        let pixels = try readPixels(cgImage: cgImage)
        let (colors, assignments) = kMeans(pixels: pixels, k: options.maxColors)
        guard !colors.isEmpty else { throw ImageVectorizationError.colorQuantizationFailed }

        var layers: [(hex: String, svgPaths: [String])] = []
        let sorted = colors.indices
            .filter { colors[$0].pixelCount > 0 }
            .sorted { colors[$0].pixelCount > colors[$1].pixelCount }

        for idx in sorted {
            let mask = makeMask(pixels: pixels, assignments: assignments, clusterIdx: idx, width: w, height: h)
            guard let maskImg = makeCGImage(fromGray: mask, width: w, height: h) else { continue }
            let paths = try extractSVGPaths(maskImage: maskImg, imageWidth: w, imageHeight: h, options: options)
            if !paths.isEmpty {
                layers.append((hex: colors[idx].hex, svgPaths: paths))
            }
        }

        guard !layers.isEmpty else { throw ImageVectorizationError.noContoursFound }

        let svgString = assembleSVG(layers: layers, width: w, height: h)
        guard let svgData = svgString.data(using: .utf8) else { throw ImageVectorizationError.svgEncodeFailed }
        guard let preview = makeQuantizedPreviewPNG(pixels: pixels, assignments: assignments, colors: colors, width: w, height: h) else {
            throw ImageVectorizationError.previewRenderFailed
        }
        return VectorizationResult(svgData: svgData, previewPNGData: preview)
    }

    // MARK: - CGImage Helpers

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func makeCGImage(fromGray bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Pixel Extraction

    private static func readPixels(cgImage: CGImage) throws -> [PixelRGB] {
        let w = cgImage.width, h = cgImage.height
        let bpr = w * 4
        var raw = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &raw, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageVectorizationError.imageDecodeFailed }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var pixels = [PixelRGB](repeating: PixelRGB(r: 0, g: 0, b: 0, alpha: 0), count: w * h)
        for i in 0..<(w * h) {
            let base = i * 4
            let a = raw[base + 3]
            if a > 0 {
                let s = 255.0 / Double(a)
                pixels[i] = PixelRGB(
                    r: UInt8(min(255.0, Double(raw[base]) * s)),
                    g: UInt8(min(255.0, Double(raw[base + 1]) * s)),
                    b: UInt8(min(255.0, Double(raw[base + 2]) * s)),
                    alpha: a
                )
            }
        }
        return pixels
    }

    // MARK: - k-means Quantization

    private static func kMeans(pixels: [PixelRGB], k: Int) -> (colors: [QuantizedColor], assignments: [Int]) {
        let opaque = pixels.indices.filter { pixels[$0].isOpaque }
        guard !opaque.isEmpty else { return ([], []) }

        var centers = kMeansPPCenters(pixels: pixels, indices: opaque, k: min(k, opaque.count))
        let nc = centers.count  // actual center count (may be < k if all pixels are same color)
        var assignments = [Int](repeating: 0, count: pixels.count)

        for _ in 0..<20 {
            var changed = false
            for i in opaque {
                let p = pixels[i]
                let best = nearestCenter(r: p.r, g: p.g, b: p.b, in: centers)
                if assignments[i] != best { changed = true; assignments[i] = best }
            }
            if !changed { break }

            var sums = [(r: Int, g: Int, b: Int, n: Int)](repeating: (0, 0, 0, 0), count: nc)
            for i in opaque {
                let c = assignments[i]; let p = pixels[i]
                sums[c].r += Int(p.r); sums[c].g += Int(p.g); sums[c].b += Int(p.b); sums[c].n += 1
            }
            for j in 0..<nc where sums[j].n > 0 {
                centers[j] = (UInt8(sums[j].r / sums[j].n), UInt8(sums[j].g / sums[j].n), UInt8(sums[j].b / sums[j].n))
            }
        }

        var counts = [Int](repeating: 0, count: nc)
        for i in opaque { counts[assignments[i]] += 1 }
        let colors = (0..<nc).map {
            QuantizedColor(r: centers[$0].0, g: centers[$0].1, b: centers[$0].2, pixelCount: counts[$0])
        }
        return (colors, assignments)
    }

    private static func kMeansPPCenters(pixels: [PixelRGB], indices: [Int], k: Int) -> [(UInt8, UInt8, UInt8)] {
        var centers: [(UInt8, UInt8, UInt8)] = []
        let first = pixels[indices[indices.count / 2]]
        centers.append((first.r, first.g, first.b))

        while centers.count < k {
            var dists = [Double](repeating: 0, count: indices.count)
            var total = 0.0
            for (n, i) in indices.enumerated() {
                let p = pixels[i]
                let d = Double(minSqDist(r: p.r, g: p.g, b: p.b, centers: centers))
                dists[n] = d; total += d
            }
            guard total > 0 else { break }
            var threshold = Double.random(in: 0..<total)
            var chosen = indices.last!
            for (n, i) in indices.enumerated() {
                threshold -= dists[n]
                if threshold <= 0 { chosen = i; break }
            }
            let cp = pixels[chosen]
            centers.append((cp.r, cp.g, cp.b))
        }
        return centers
    }

    private static func nearestCenter(r: UInt8, g: UInt8, b: UInt8, in centers: [(UInt8, UInt8, UInt8)]) -> Int {
        var best = 0, bestD = Int.max
        for (i, c) in centers.enumerated() {
            let d = sqDist(r, g, b, c.0, c.1, c.2)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    private static func minSqDist(r: UInt8, g: UInt8, b: UInt8, centers: [(UInt8, UInt8, UInt8)]) -> Int {
        centers.map { sqDist(r, g, b, $0.0, $0.1, $0.2) }.min() ?? 0
    }

    private static func sqDist(_ r1: UInt8, _ g1: UInt8, _ b1: UInt8,
                                _ r2: UInt8, _ g2: UInt8, _ b2: UInt8) -> Int {
        let dr = Int(r1) - Int(r2); let dg = Int(g1) - Int(g2); let db = Int(b1) - Int(b2)
        return dr * dr + dg * dg + db * db
    }

    // MARK: - Binary Mask

    private static func makeMask(pixels: [PixelRGB], assignments: [Int], clusterIdx: Int, width: Int, height: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in pixels.indices where pixels[i].isOpaque && assignments[i] == clusterIdx {
            mask[i] = 255
        }
        return mask
    }

    // MARK: - Contour Detection

    private static func extractSVGPaths(maskImage: CGImage, imageWidth: Int, imageHeight: Int, options: VectorizationOptions) throws -> [String] {
        let req = VNDetectContoursRequest()
        req.contrastAdjustment = options.contrastAdjustment
        req.detectsDarkOnLight = false  // 白(255)領域を検出

        let handler = VNImageRequestHandler(cgImage: maskImage, options: [:])
        do {
            try handler.perform([req])
        } catch {
            throw ImageVectorizationError.contourDetectionFailed(underlying: error)
        }

        guard let obs = req.results?.first else { return [] }

        let minArea = options.minContourAreaFraction
        var paths: [String] = []

        for contour in obs.topLevelContours {
            guard contourArea(contour.normalizedPath) >= minArea else { continue }
            paths.append(pathToSVG(contour.normalizedPath, w: imageWidth, h: imageHeight))
            for child in contour.childContours {
                guard contourArea(child.normalizedPath) >= minArea else { continue }
                paths.append(pathToSVG(child.normalizedPath, w: imageWidth, h: imageHeight))
            }
        }
        return paths
    }

    // MARK: - Contour Area (Shoelace)

    private static func contourArea(_ path: CGPath) -> CGFloat {
        var pts: [CGPoint] = []
        path.applyWithBlock { el in
            switch el.pointee.type {
            case .moveToPoint, .addLineToPoint: pts.append(el.pointee.points[0])
            case .addQuadCurveToPoint:          pts.append(el.pointee.points[1])
            case .addCurveToPoint:              pts.append(el.pointee.points[2])
            default: break
            }
        }
        guard pts.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(area) / 2
    }

    // MARK: - CGPath → SVG path string

    private static func pathToSVG(_ path: CGPath, w: Int, h: Int) -> String {
        let fw = CGFloat(w), fh = CGFloat(h)
        // VN: origin=bottom-left, Y up → SVG: origin=top-left, Y down
        func px(_ p: CGPoint) -> String { fmtF(p.x * fw) + "," + fmtF((1.0 - p.y) * fh) }

        var d = ""
        path.applyWithBlock { el in
            let pts = el.pointee.points
            switch el.pointee.type {
            case .moveToPoint:      d += "M" + px(pts[0])
            case .addLineToPoint:   d += "L" + px(pts[0])
            case .addQuadCurveToPoint:
                d += "Q" + px(pts[0]) + " " + px(pts[1])
            case .addCurveToPoint:
                d += "C" + px(pts[0]) + " " + px(pts[1]) + " " + px(pts[2])
            case .closeSubpath:     d += "Z"
            @unknown default: break
            }
        }
        return d
    }

    // MARK: - SVG Assembly

    private static func assembleSVG(layers: [(hex: String, svgPaths: [String])], width: Int, height: Int) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) \(height)\" width=\"\(width)\" height=\"\(height)\">\n"
        for layer in layers {
            s += "  <path fill=\"\(layer.hex)\" d=\"\(layer.svgPaths.joined())\"/>\n"
        }
        s += "</svg>"
        return s
    }

    // MARK: - Quantized Preview PNG (thread-safe, no AppKit)

    private static func makeQuantizedPreviewPNG(
        pixels: [PixelRGB], assignments: [Int], colors: [QuantizedColor],
        width: Int, height: Int
    ) -> Data? {
        // Build RGBA pixel buffer using quantized cluster colors
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<pixels.count {
            let p = pixels[i]
            let base = i * 4
            if p.alpha < 128 {
                // transparent pixel
            } else {
                let ci = assignments[i]
                let c = ci < colors.count ? colors[ci] : QuantizedColor(r: p.r, g: p.g, b: p.b, pixelCount: 0)
                rgba[base] = c.r; rgba[base + 1] = c.g; rgba[base + 2] = c.b; rgba[base + 3] = p.alpha
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return output as Data
    }

    private static func fmtF(_ v: CGFloat) -> String { String(format: "%.1f", v) }
}
