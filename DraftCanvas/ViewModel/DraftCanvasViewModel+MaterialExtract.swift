import Foundation
import CoreImage

extension DraftCanvasViewModel {

    func startMaterialExtraction(item: ProjectItem) {
        let projectID = selectedProjectID ?? item.projectID

        let job = GenerationJob(
            index: jobsByProject[projectID]?.count ?? 0,
            prompt: "素材分解: \(item.prompt.prefix(30))",
            aspectRatio: item.aspectRatio
        )
        upsert(job, into: projectID)

        let fileURL = projectStore.resolvedFileURL(for: item)
        extractingItemID = item.id

        materialExtractionTask = Task {
            var running = job
            running.status = .running
            upsert(running, into: projectID)

            do {
                let inputData = try Data(contentsOf: fileURL)
                let session = try await MaterialExtractor.detect(from: inputData)

                var succeeded = running
                succeeded.status = .succeeded
                upsert(succeeded, into: projectID)

                extractingItemID = nil
                materialExtractionTask = nil
                materialExtractionPreview = MaterialExtractionPreview(item: item, session: session)
                logs.append("素材分解検出完了: \(session.instances.count) 個 (\(item.id))")
            } catch {
                extractingItemID = nil
                materialExtractionTask = nil
                var failed = running
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                upsert(failed, into: projectID)
                let message = (error as? MaterialExtractionError)?.localizedDescription
                    ?? String(localized: "素材分解に失敗しました")
                errorToast = message
                logs.append("素材分解失敗: \(error.localizedDescription)")
            }
        }
    }

    func commitMaterialExtraction(
        originalItem: ProjectItem,
        session: MaterialExtractor.ExtractionSession,
        instances: [MaterialExtractor.DetectedInstance],
        selectedInstanceIDs: Set<UUID>,
        removeBackground: Bool = false
    ) {
        let projectID = selectedProjectID ?? originalItem.projectID
        materialExtractionPreview = nil

        let chosen = instances.filter { selectedInstanceIDs.contains($0.id) }
        guard !chosen.isEmpty else { return }

        let storeRef = projectStore
        let thumbnailRef = thumbnailStore

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // session.ciCtx はメインスレッド作成の Metal CIContext のためバックグラウンドから共有すると GPU 競合でフリーズする
            let renderCtx = CIContext(options: [
                .workingColorSpace: session.sRGB,
                .outputColorSpace: session.sRGB
            ])

            var newItems: [ProjectItem] = []

            for inst in chosen {
                do {
                    let instToRender: MaterialExtractor.DetectedInstance
                    if removeBackground {
                        instToRender = MaterialExtractor.processUserInstance(session: session, instance: inst)
                    } else {
                        // 背景除去オフ: 全インスタンスをソリッド矩形マスクで矩形クロップ
                        instToRender = MaterialExtractor.makeUserInstance(
                            imageBBox: inst.imageBoundingBox,
                            imagePixelSize: session.imagePixelSize,
                            extent: session.extent
                        )
                    }
                    let png = try MaterialExtractor.renderInstancePNG(
                        session: session, instance: instToRender,
                        cropToBoundingBox: true, ciCtx: renderCtx
                    )
                    let box = inst.imageBoundingBox
                    let actualRatio: CGFloat? = box.height > 0 ? box.width / box.height : nil
                    let aspectRatio = self.aspectRatioFromImageData(png)

                    let newItem = ProjectItem(
                        projectID: projectID,
                        prompt: originalItem.prompt,
                        aspectRatio: aspectRatio,
                        actualAspectRatio: actualRatio,
                        editedFromItemID: originalItem.id,
                        isBackgroundRemoved: removeBackground
                    )
                    try storeRef.writeItemData(png, for: newItem)
                    thumbnailRef.writeThumbnail(from: png, item: newItem)
                    newItems.append(newItem)
                } catch {
                    await MainActor.run { [weak self] in
                        self?.logs.append("素材保存失敗 (id=\(inst.id)): \(error.localizedDescription)")
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.items.append(contentsOf: newItems)
                if let idx = self.projects.firstIndex(where: { $0.id == projectID }) {
                    self.projects[idx].updatedAt = Date()
                }
                self.saveState()
                self.logs.append("素材分解保存完了: \(newItems.count) 件追加")
            }
        }
    }

    func cancelMaterialExtraction() {
        materialExtractionTask?.cancel()
        materialExtractionTask = nil
        materialExtractionPreview = nil
    }
}
