import SwiftUI

struct ReleaseNotesView: View {
    @State private var sections: [ChangelogSection] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !loadError.isNilOrEmpty {
                    Text(loadError ?? "")
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else if sections.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        VersionSectionView(section: section)
                        if index < sections.count - 1 {
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { load() }
    }

    private func load() {
        do {
            sections = try ReleaseNotesLoader.load()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct VersionSectionView: View {
    let section: ChangelogSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.version)
                    .font(.title2.bold())
                Spacer()
                if !section.date.isEmpty {
                    Text(section.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            ForEach(section.categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(category.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                                .frame(width: 12, alignment: .leading)
                            Text(item)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
