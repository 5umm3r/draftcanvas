import SwiftUI

struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let sources: [(name: String, file: String)] = [
        ("vtracer", "vtracer"),
        ("visioncortex", "visioncortex"),
        ("image", "image"),
        ("oxipng", "oxipng"),
        ("pngquant", "pngquant"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("オープンソースライセンス")
                    .font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Self.sources, id: \.name) { source in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(source.name)
                                .font(.title3.weight(.semibold))
                            Text(licenseText(source.file))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640, height: 520)
    }

    private func licenseText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "(\(name) のライセンスを読み込めませんでした)"
        }
        return text
    }
}
