import CoreImage

/// 小さい素材を近接グループにまとめる Stage
struct GroupSmallNearbyStage: ExtractionStage {
    struct Input {
        let instances: [MaterialExtractor.DetectedInstance]
        let imageSize: CGSize
        let extent: CGRect
    }
    typealias Output = [MaterialExtractor.DetectedInstance]

    func run(_ input: Input) throws -> [MaterialExtractor.DetectedInstance] {
        let instances = input.instances
        let imageSize = input.imageSize
        let extent = input.extent
        let n = instances.count
        guard n > 0 else { return instances }

        // 1. 各 instance の対角長を計算
        let diags = instances.map { inst -> CGFloat in
            let w = inst.imageBoundingBox.width
            let h = inst.imageBoundingBox.height
            return sqrt(w * w + h * h)
        }

        // 2. medianD（対角長の中央値）を計算
        let sortedDiags = diags.sorted()
        let medianD = sortedDiags[sortedDiags.count / 2]

        // 3. 小素材判定
        let minSide = min(imageSize.width, imageSize.height)
        let isSmall = diags.map { d in
            d < medianD * 0.6 && d < minSide * 0.05
        }

        // 小素材インデックス一覧
        let smallIndices = (0..<n).filter { isSmall[$0] }

        // 4. 小素材が 1 個以下なら即返却
        guard smallIndices.count >= 2 else { return instances }

        // 小素材の中心座標
        let smallCenters = smallIndices.map { i -> CGPoint in
            let box = instances[i].imageBoundingBox
            return CGPoint(x: box.midX, y: box.midY)
        }

        // 各小素材と他の全小素材の最近傍距離を計算
        var nearestDists: [CGFloat] = []
        for i in 0..<smallCenters.count {
            var minDist = CGFloat.infinity
            for j in 0..<smallCenters.count {
                guard i != j else { continue }
                let dx = smallCenters[i].x - smallCenters[j].x
                let dy = smallCenters[i].y - smallCenters[j].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < minDist { minDist = dist }
            }
            if minDist < .infinity { nearestDists.append(minDist) }
        }

        guard !nearestDists.isEmpty else { return instances }

        let sortedNearestDists = nearestDists.sorted()
        let clusterDist = sortedNearestDists[sortedNearestDists.count / 2]
        let mergeDist = clusterDist * 1.8

        // 5. 距離 < mergeDist で Union-Find（小素材インデックス同士）
        var parent = [Int](0..<n)

        for ai in 0..<smallIndices.count {
            for bi in (ai + 1)..<smallIndices.count {
                let a = smallIndices[ai]
                let b = smallIndices[bi]
                let dx = smallCenters[ai].x - smallCenters[bi].x
                let dy = smallCenters[ai].y - smallCenters[bi].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < mergeDist {
                    UnionFind.unionSets(a, b, &parent)
                }
            }
        }

        // 6. グループ化した結果を DetectedInstance にまとめる
        var groups: [Int: [Int]] = [:]
        for i in smallIndices {
            let root = UnionFind.findRoot(i, &parent)
            groups[root, default: []].append(i)
        }

        var result: [MaterialExtractor.DetectedInstance] = []

        // グループ化されない中・大素材はそのまま追加
        let groupedIndices = Set(smallIndices)
        for i in 0..<n {
            if !groupedIndices.contains(i) {
                result.append(instances[i])
            }
        }

        // グループ化された小素材を合成
        for (_, group) in groups {
            if group.count == 1 {
                // 単独小素材はそのまま
                result.append(instances[group[0]])
                continue
            }

            // bbox を union
            var unionBBox = instances[group[0]].imageBoundingBox
            for i in group.dropFirst() {
                unionBBox = unionBBox.union(instances[i].imageBoundingBox)
            }

            // maskCI を CIFilter.maximumCompositing() で合成
            var mergedMask = instances[group[0]].maskCI
            for i in group.dropFirst() {
                guard let filter = CIFilter(name: "CIMaximumCompositing") else { continue }
                filter.setValue(instances[i].maskCI, forKey: kCIInputImageKey)
                filter.setValue(mergedMask, forKey: kCIInputBackgroundImageKey)
                if let output = filter.outputImage {
                    mergedMask = output
                }
            }
            mergedMask = mergedMask.cropped(to: extent)

            // normalizedBoundingBox を再計算
            let normalizedBoundingBox = CGRect(
                x: unionBBox.minX / imageSize.width,
                y: unionBBox.minY / imageSize.height,
                width: unionBBox.width / imageSize.width,
                height: unionBBox.height / imageSize.height
            )

            result.append(MaterialExtractor.DetectedInstance(
                id: UUID(),
                source: .grouped,
                normalizedBoundingBox: normalizedBoundingBox,
                imageBoundingBox: unionBBox,
                maskCI: mergedMask
            ))
        }

        return result
    }
}
