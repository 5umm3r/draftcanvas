import CoreImage

/// Vision と CCA の検出結果を IoU でマージし重複を除去する Stage
struct MergeByIoUStage: ExtractionStage {
    struct Input {
        let visionInstances: [MaterialExtractor.DetectedInstance]
        let ccaInstances: [MaterialExtractor.DetectedInstance]
    }
    typealias Output = [MaterialExtractor.DetectedInstance]

    func run(_ input: Input) throws -> [MaterialExtractor.DetectedInstance] {
        let all = input.visionInstances + input.ccaInstances
        let n = all.count
        guard n > 0 else { return [] }

        // IoU 計算
        func iou(_ a: CGRect, _ b: CGRect) -> Double {
            let intersection = a.intersection(b)
            if intersection.isNull { return 0 }
            let intersectionArea = Double(intersection.width * intersection.height)
            let unionArea = Double(a.width * a.height) + Double(b.width * b.height) - intersectionArea
            return unionArea > 0 ? intersectionArea / unionArea : 0
        }

        // Union-Find
        var parent = [Int](0..<n)

        for i in 0..<n {
            for j in (i + 1)..<n {
                if iou(all[i].normalizedBoundingBox, all[j].normalizedBoundingBox) >= 0.30 {
                    UnionFind.unionSets(i, j, &parent)
                }
            }
        }

        // グループ化
        var groups: [Int: [Int]] = [:]
        for i in 0..<n {
            let root = UnionFind.findRoot(i, &parent)
            groups[root, default: []].append(i)
        }

        // 各グループから代表を選出
        var result: [MaterialExtractor.DetectedInstance] = []
        for (_, group) in groups {
            // Vision インスタンスを優先、なければ CCA
            let visionInGroup = group.filter { all[$0].source == .vision }
            let candidates = visionInGroup.isEmpty ? group : visionInGroup
            // 面積が最大のものを代表に
            let rep = candidates.max(by: {
                let a = all[$0].normalizedBoundingBox
                let b = all[$1].normalizedBoundingBox
                return Double(a.width * a.height) < Double(b.width * b.height)
            })!
            result.append(all[rep])
        }

        return result
    }
}
