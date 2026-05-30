import Foundation

extension DraftCanvasViewModel {
    func refreshAccountUsageIfStale() {
        let isStale = accountUsageStatusFetchedAt.map { Date().timeIntervalSince($0) > 30 } ?? true
        guard isStale else { return }
        refreshAccountUsage()
    }

    func refreshAccountUsage() {
        guard accountUsageRefreshTask == nil else { return }

        isRefreshingAccountUsage = true
        accountUsagePrewarmFailed = false
        logs.append("Codexアカウントと使用量を取得します。")

        let client = self.accountClient
        let refreshTask = Task.detached { try await client.readAccountUsageStatus() }
        accountUsageRefreshTask = refreshTask

        Task {
            do {
                let status = try await refreshTask.value
                self.accountUsageStatus = status
                self.accountUsageStatusFetchedAt = Date()
                self.isRefreshingAccountUsage = false
                self.accountUsageRefreshTask = nil
                self.logs.append("Codexアカウントと使用量を更新しました。")
            } catch {
                self.isRefreshingAccountUsage = false
                self.accountUsageRefreshTask = nil
                self.accountUsagePrewarmFailed = true
                self.logs.append("Codexアカウントと使用量の取得に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    func relaunchAndRefreshAccountUsage() {
        accountClient.stop()
        availableModels = []
        codexVersion = "--"
        prewarmAndRefresh(forceMetadata: true)
    }

    func prewarmAndRefresh(forceMetadata: Bool = false) {
        accountUsagePrewarmFailed = false
        Task {
            do {
                try await accountClient.start()
            } catch {
                await MainActor.run {
                    self.accountUsagePrewarmFailed = true
                    self.logs.append("codex app-server の起動に失敗しました: \(error.localizedDescription)")
                }
                return
            }
            let path = accountClient.codexExecutablePath
            let shouldRefreshModels = forceMetadata || availableModels.isEmpty
            let shouldRefreshVersion = forceMetadata || codexVersion == "--"
            await withTaskGroup(of: Void.self) { group in
                if shouldRefreshModels {
                    group.addTask { await self.refreshAvailableModels() }
                }
                if shouldRefreshVersion {
                    group.addTask {
                        let v = await CodexAppServerClient.fetchVersion(executablePath: path)
                        await MainActor.run { self.codexVersion = v ?? "--" }
                    }
                }
            }
            refreshAccountUsageIfStale()
        }
    }

    func refreshAvailableModels() async {
        do {
            let models = try await accountClient.listModels(includeHidden: false)
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
        accountClient.stop()
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
