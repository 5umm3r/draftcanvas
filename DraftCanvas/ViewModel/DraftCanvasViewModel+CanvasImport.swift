import AppKit
import Foundation

extension DraftCanvasViewModel {
    func importImageToCanvas() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.prompt = "インポート"
        panel.message = "キャンバスにインポートする画像を選択してください。"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let projectID = selectedProjectID ?? createProject().id
        for url in panel.urls {
            importImageAsProjectItem(url: url, projectID: projectID)
        }
    }

    func importImageAsProjectItem(url: URL, projectID: UUID) {
        do {
            let pngData = try loadAndNormalizeImage(from: url)
            let aspectRatio = aspectRatioFromImageData(pngData)
            let name = url.deletingPathExtension().lastPathComponent
            let newItem = ProjectItem(
                projectID: projectID,
                prompt: name,
                aspectRatio: aspectRatio,
                isImported: true
            )
            try projectStore.writeItemData(pngData, for: newItem)
            items.append(newItem)
            thumbnailStore.writeThumbnail(from: pngData, item: newItem)
            if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
            logs.append("画像をインポートしました: \(url.lastPathComponent)")
        } catch {
            errorToast = "画像のインポートに失敗しました"
            logs.append("インポートエラー: \(error.localizedDescription)")
        }
    }

    func importImageAsProjectItem(image: NSImage, projectID: UUID) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            errorToast = "画像の変換に失敗しました"
            return
        }
        let aspectRatio = aspectRatioFromImageData(pngData)
        let newItem = ProjectItem(
            projectID: projectID,
            prompt: "Imported Image",
            aspectRatio: aspectRatio,
            isImported: true
        )
        do {
            try projectStore.writeItemData(pngData, for: newItem)
            items.append(newItem)
            thumbnailStore.writeThumbnail(from: pngData, item: newItem)
            if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].updatedAt = Date()
            }
            saveState()
            logs.append("画像をインポートしました (ドラッグ&ドロップ)")
        } catch {
            errorToast = "画像のインポートに失敗しました"
            logs.append("インポートエラー: \(error.localizedDescription)")
        }
    }
}
