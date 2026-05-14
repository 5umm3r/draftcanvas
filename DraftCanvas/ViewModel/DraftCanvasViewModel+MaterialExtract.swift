import Foundation

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

        Task {
            var running = job
            running.status = .running
            upsert(running, into: projectID)

            do {
                let inputData = try Data(contentsOf: fileURL)
                let session = try await MaterialExtractor.detect(from: inputData)

                var succeeded = running
                succeeded.status = .succeeded
                upsert(succeeded, into: projectID)

                materialExtractionPreview = MaterialExtractionPreview(item: item, session: session)
                logs.append("素材分解検出完了: \(session.instances.count) 個 (\(item.id))")
            } catch {
                var failed = running
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                upsert(failed, into: projectID)
                let message = (error as? MaterialExtractionError)?.localizedDescription
                    ?? "素材分解に失敗しました"
                errorToast = message
                logs.append("素材分解失敗: \(error.localizedDescription)")
            }
        }
    }

    func commitMaterialExtraction(
        originalItem: ProjectItem,
        session: MaterialExtractor.ExtractionSession,
        selectedInstanceIDs: Set<UUID>
    ) {
        let projectID = selectedProjectID ?? originalItem.projectID
        materialExtractionPreview = nil

        let chosen = session.instances.filter { selectedInstanceIDs.contains($0.id) }
        guard !chosen.isEmpty else { return }

        let storeRef = projectStore
        let thumbnailRef = thumbnailStore

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            var newItems: [ProjectItem] = []

            for inst in chosen {
                do {
                    let png = try MaterialExtractor.renderInstancePNG(
                        session: session, instance: inst, cropToBoundingBox: true
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
                        isBackgroundRemoved: true
                    )
                    try storeRef.writeItemData(png, for: newItem)
                    thumbnailRef.writeThumbnail(from: png, item: newItem)
                    newItems.append(newItem)
                } catch {
                    await MainActor.run { [weak self] in
                        self?.logs.append("素材保存失敗 (idx=\(inst.visionInstanceIndex)): \(error.localizedDescription)")
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
        materialExtractionPreview = nil
    }
}
