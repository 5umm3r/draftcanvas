import SwiftUI

struct LicensesWindow: View {
    @State private var selection: String? = LicensesCatalog.all.first?.id

    var body: some View {
        NavigationSplitView {
            List(LicensesCatalog.all, selection: $selection) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                    Text(entry.licenseType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 180)
            .navigationTitle(String(localized: "ライセンス"))
        } detail: {
            if let id = selection,
               let entry = LicensesCatalog.all.first(where: { $0.id == id }) {
                LicenseDetailView(entry: entry)
            } else {
                ContentUnavailableView(String(localized: "ライセンスを選択"), systemImage: "doc.text")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct LicenseDetailView: View {
    let entry: LicenseEntry
    @State private var licenseText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.name)
                        .font(.title2.bold())
                    if !entry.version.isEmpty {
                        Text("v\(entry.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Label(entry.licenseType, systemImage: "doc.plaintext")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let dest = URL(string: entry.url) {
                        Link(entry.url, destination: dest)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                if let note = entry.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(licenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .task(id: entry.id) {
            licenseText = entry.licenseText()
        }
    }
}
