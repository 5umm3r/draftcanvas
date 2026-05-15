import Foundation

extension DraftCanvasViewModel {
    func refreshAccountUsage() {
        guard !isRefreshingAccountUsage else { return }

        isRefreshingAccountUsage = true
        accountUsagePrewarmFailed = false
        logs.append("Codexアカウントと使用量を取得します。")

        Task {
            do {
                let status = try await self.client.readAccountUsageStatus()
                await MainActor.run {
                    self.accountUsageStatus = status
                    self.syncSessionWindows(from: status)
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

    func syncSessionWindows(from status: CodexAccountUsageStatus) {
        if let d = status.primaryResetDate {
            let epoch = d.timeIntervalSince1970
            if session5hResetEpoch == 0 {
                session5hResetEpoch = epoch
            } else if abs(epoch - session5hResetEpoch) > 1.0 {
                session5hCount = pendingFiveHDelta
                session5hResetEpoch = epoch
            }
            pendingFiveHDelta = 0
        }
        if let d = status.secondaryResetDate {
            let epoch = d.timeIntervalSince1970
            if sessionWeeklyResetEpoch == 0 {
                sessionWeeklyResetEpoch = epoch
            } else if abs(epoch - sessionWeeklyResetEpoch) > 1.0 {
                sessionWeeklyCount = pendingWeeklyDelta
                sessionWeeklyResetEpoch = epoch
            }
            pendingWeeklyDelta = 0
        }
    }

    func resetAllCounters() {
        session5hCount = 0
        sessionWeeklyCount = 0
        totalGeneratedImages = 0
    }

    func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        Task {
            do {
                _ = try await client.sendRequest(method: "account/logout")
                await MainActor.run {
                    self.accountUsageStatus = .unavailable
                    self.isLoggingOut = false
                    self.logs.append("ログアウトしました。")
                }
                refreshAccountUsage()
            } catch {
                await MainActor.run {
                    self.isLoggingOut = false
                    self.errorToast = L("ログアウトに失敗しました")
                    self.logs.append("ログアウト失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    func prewarmAndRefresh() {
        accountUsagePrewarmFailed = false
        Task {
            await refreshAvailableModels()
        }
        Task.detached(priority: .background) { [weak self] in
            let path = await MainActor.run { self?.client.codexExecutablePath ?? "" }
            let version = await CodexAppServerClient.fetchVersion(executablePath: path)
            await MainActor.run { self?.codexVersion = version ?? "--" }
        }
        refreshAccountUsage()
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
