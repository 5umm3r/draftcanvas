import Foundation

struct LicenseEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let url: String
    let licenseType: String
    let note: String?

    init(id: String, name: String, version: String, url: String, licenseType: String, note: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.url = url
        self.licenseType = licenseType
        self.note = note
    }

    func licenseText() -> String {
        guard let fileURL = Bundle.main.url(forResource: id, withExtension: "txt", subdirectory: "Licenses"),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return "License text not available."
        }
        return text
    }
}

enum LicensesCatalog {
    static let all: [LicenseEntry] = [
        LicenseEntry(
            id: "vtracer",
            name: "vtracer",
            version: "0.6.5",
            url: "https://github.com/visioncortex/vtracer",
            licenseType: "MIT"
        ),
        LicenseEntry(
            id: "visioncortex",
            name: "visioncortex",
            version: "0.8.10",
            url: "https://github.com/visioncortex/visioncortex",
            licenseType: "MIT OR Apache-2.0"
        ),
        LicenseEntry(
            id: "image",
            name: "image",
            version: "0.23.14",
            url: "https://github.com/image-rs/image",
            licenseType: "MIT"
        ),
        LicenseEntry(
            id: "oxipng",
            name: "oxipng",
            version: "9.1.5",
            url: "https://github.com/shssoichiro/oxipng",
            licenseType: "MIT"
        ),
        LicenseEntry(
            id: "pngquant",
            name: "pngquant",
            version: "2.x",
            url: "https://pngquant.org/",
            licenseType: "GPL v3",
            note: "Used as a standalone binary via subprocess invocation — not linked to Draft Canvas."
        ),
    ]
}
