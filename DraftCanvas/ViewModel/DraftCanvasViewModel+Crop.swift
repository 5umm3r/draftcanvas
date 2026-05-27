import AppKit
import Foundation

extension DraftCanvasViewModel {
    func openCropEditor(for item: ProjectItem) {
        cropTarget = item
    }

    func commitCrop(item: ProjectItem, rect: CGRect, template: AspectTemplate) {
        let projectID = selectedProjectID ?? item.projectID
        cropTarget = nil

        // isCropped アイテムを再編集する場合は元アイテムの画像から切り出す
        let sourceItemID: UUID = item.isCropped ? (item.editedFromItemID ?? item.id) : item.id
        guard let sourceItem = items.first(where: { $0.id == sourceItemID }) else {
            errorToast = String(localized: "切り出し元画像が見つかりませんでした")
            return
        }

        let sourceURL = projectStore.resolvedFileURL(for: sourceItem)
        guard let sourceData = try? Data(contentsOf: sourceURL),
              let imageSource = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            errorToast = String(localized: "画像を読み込めませんでした")
            return
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // CGImage.cropping は top-left origin — rect と同じ座標系なので反転不要
        // 浮動小数点誤差で非整数になると CGImage が切り上げてサイズが+1pxになるため整数丸め
        let rawRect = CGRect(origin: rect.origin, size: rect.size)
            .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        let cropRect = CGRect(
            x: rawRect.origin.x.rounded(),
            y: rawRect.origin.y.rounded(),
            width: rawRect.size.width.rounded(),
            height: rawRect.size.height.rounded()
        ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard let cropped = cgImage.cropping(to: cropRect),
              let pngData = encodePNG(cgImage: cropped)
        else {
            errorToast = String(localized: "トリミングに失敗しました")
            return
        }

        let newAspectRatio = cropRect.height > 0 ? cropRect.width / cropRect.height : 1.0
        let params = CropParameters(rect: rect, template: template)

        if item.isCropped {
            // 同一派生アイテムを上書き更新
            guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
            do {
                try projectStore.writeItemData(pngData, for: item)
                try projectStore.writeCropParameters(params, id: item.id)
                thumbnailStore.writeThumbnail(from: pngData, item: item)
                originalImageStore.evict(url: projectStore.resolvedFileURL(for: item))
                // actualAspectRatio は let なので新インスタンスに置き換え
                let updated = ProjectItem(
                    id: item.id,
                    projectID: item.projectID,
                    prompt: item.prompt,
                    revisedPrompt: item.revisedPrompt,
                    aspectRatio: item.aspectRatio,
                    actualAspectRatio: newAspectRatio,
                    createdAt: item.createdAt,
                    errorMessage: item.errorMessage,
                    editedFromItemID: item.editedFromItemID,
                    hasSVG: false,
                    isBackgroundRemoved: item.isBackgroundRemoved,
                    isCropped: true,
                    isImported: item.isImported,
                    tags: item.tags,
                    sketchSourcePath: item.sketchSourcePath
                )
                items[idx] = updated
                saveState()
                logs.append("トリミング再編集保存完了: \(item.id)")
            } catch {
                errorToast = String(localized: "トリミング結果の保存に失敗しました")
                logs.append("トリミング保存失敗: \(error.localizedDescription)")
            }
        } else {
            // 新規派生アイテム作成
            let newItem = ProjectItem(
                projectID: projectID,
                prompt: item.prompt,
                revisedPrompt: item.revisedPrompt,
                aspectRatio: item.aspectRatio,
                actualAspectRatio: newAspectRatio,
                editedFromItemID: item.id,
                isCropped: true
            )
            do {
                try projectStore.writeItemData(pngData, for: newItem)
                try projectStore.writeCropParameters(params, id: newItem.id)
                // 元アイテムの直後に挿入
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items.insert(newItem, at: items.index(after: idx))
                } else {
                    items.append(newItem)
                }
                thumbnailStore.writeThumbnail(from: pngData, item: newItem)
                if let idx = projects.firstIndex(where: { $0.id == projectID }) {
                    projects[idx].updatedAt = Date()
                }
                saveState()
                logs.append("トリミング保存完了: \(newItem.id)")
            } catch {
                errorToast = String(localized: "トリミング結果の保存に失敗しました")
                logs.append("トリミング保存失敗: \(error.localizedDescription)")
            }
        }
    }

    private func encodePNG(cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }
}
