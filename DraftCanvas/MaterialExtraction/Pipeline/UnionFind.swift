// Union-Find ユーティリティ
// 元の MaterialExtractor.swift の findRoot/unionSets から切り出し。

enum UnionFind {
    /// パス圧縮付き Union-Find のルート探索
    static func findRoot(_ i: Int, _ parent: inout [Int]) -> Int {
        var x = i
        while parent[x] != x {
            parent[x] = parent[parent[x]]
            x = parent[x]
        }
        return x
    }

    /// Union-Find の結合操作
    static func unionSets(_ a: Int, _ b: Int, _ parent: inout [Int]) {
        let ra = findRoot(a, &parent)
        let rb = findRoot(b, &parent)
        if ra != rb { parent[ra] = rb }
    }
}
