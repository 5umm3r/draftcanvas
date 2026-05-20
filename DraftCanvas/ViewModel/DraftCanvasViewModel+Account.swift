import Foundation

extension DraftCanvasViewModel {
    func refreshAccountUsage() {
        guard !isRefreshingAccountUsage, generatingProjectIDs.isEmpty else { return }

        isRefreshingAccountUsage = true
        accountUsagePrewarmFailed = false
        logs.append("Codexアカウントと使用量を取得します。")

        Task {
            do {
                let status = try await self.client.readAccountUsageStatus()
                await MainActor.run {
                    self.accountUsageStatus = status
                    self.accountUsageStatusFetchedAt = Date()
                    self.isRefreshingAccountUsage = false
                    self.logs.append("Codexアカウントと使用量を更新しました。")
                }
            } catch {
                await MainActor.run {
                    self.accountUsageStatus = .unavailable
                    self.isRefreshingAccountUsage = false
                    self.accountUsagePrewarmFailed = true
                    self.logs.append("Codexアカウントと使用量の取得に失敗しました: \(error.localizedDescription)")
                }
            }
        }
    }

    func relaunchAndRefreshAccountUsage() {
        client.stop()
        prewarmAndRefresh()
    }

    func prewarmAndRefresh() {
        accountUsagePrewarmFailed = false
        Task {
            do {
                try await client.start()
            } catch {
                await MainActor.run {
                    self.accountUsagePrewarmFailed = true
                    self.logs.append("codex app-server の起動に失敗しました: \(error.localizedDescription)")
                }
                return
            }
            let path = client.codexExecutablePath
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.refreshAvailableModels() }
                group.addTask {
                    let v = await CodexAppServerClient.fetchVersion(executablePath: path)
                    await MainActor.run { self.codexVersion = v ?? "--" }
                }
            }
            refreshAccountUsage()
        }
    }

    func refreshAvailableModels() async {
        do {
            let models = try await client.listModels(includeHidden: false)
            self.availableModels = models
            normalizeProjectModelSelection()
        } catch {
            logs.append("モデル一覧取得失敗: \(error.localizedDescription)")
        }
    }

    func normalizeProjectModelSelection() {
        let validIDs = Set(availableModels.map(\.id))
        guard let fallbackID = availableModels.first(where: \.isDefault)?.id
                ?? availableModels.first?.id else { return }

        for index in projects.indices {
            if projects[index].model.isEmpty || !validIDs.contains(projects[index].model) {
                projects[index].model = fallbackID
            }
            if let model = availableModels.first(where: { $0.id == projects[index].model }),
               !model.supportedReasoningEfforts.contains(projects[index].reasoningEffort) {
                projects[index].reasoningEffort = model.defaultReasoningEffort
            }
        }
        if draftInputs.model.isEmpty || !validIDs.contains(draftInputs.model) {
            draftInputs.model = fallbackID
        }
        for (key, var inputs) in inputsByProject {
            if inputs.model.isEmpty || !validIDs.contains(inputs.model) {
                inputs.model = fallbackID
                inputsByProject[key] = inputs
            }
        }
        saveState()
    }

    func stopServer() {
        client.stop()
        logs.append("codex app-server を停止しました。")
    }

    func cancelEditingHistoryItem() {
        guard let id = effectiveProjectID else { return }
        var inputs = inputsByProject[id] ?? ProjectInputs()
        if let editSource = inputs.editSource, editSource.isInpainting {
            projectStore.cleanupMaskFiles(id: editSource.projectItemID)
        }
        if let attached = inputs.attachedImage {
            projectStore.cleanupAttachment(id: attached.id)
        }
        inputs.attachedImage = nil
        inputs.editSource = nil
        inputsByProject[id] = inputs
        activeEditProjectID = nil
    }
}
