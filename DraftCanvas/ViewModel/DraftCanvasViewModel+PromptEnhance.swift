import Foundation

extension DraftCanvasViewModel {
    func enhancePrompt() {
        let promptText = currentInputs.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty, !isEnhancingPrompt else { return }
        guard !availableModels.isEmpty else {
            errorToast = String(localized: "利用可能なモデルがありません")
            return
        }

        isEnhancingPrompt = true
        logs.append("プロンプトエンハンス開始")

        enhanceTask = Task {
            do {
                try await client.start()

                let model = Self.selectFastLowCostModel(from: availableModels)
                logs.append("エンハンスモデル: \(model.displayName) (\(model.id))")
                let threadID = try await client.startThread(model: model.id, reasoningEffort: "low")
                let turnPrompt = PromptEnhancer.buildPrompt(
                    userPrompt: promptText,
                    languageMode: promptLanguageMode
                )

                let result = try await withThrowingTaskGroup(of: CodexTurnResult.self) { group in
                    group.addTask {
                        try await self.client.runTurn(threadID: threadID, prompt: turnPrompt)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                        throw DraftCanvasError.rpcError(String(localized: "プロンプトエンハンスがタイムアウトしました"))
                    }
                    guard let r = try await group.next() else {
                        throw DraftCanvasError.rpcError(String(localized: "エンハンス結果を取得できませんでした"))
                    }
                    group.cancelAll()
                    return r
                }

                var enhanced = result.assistantText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let quoteChars = CharacterSet(charactersIn: "\"'`")
                while enhanced.hasPrefix("\"") || enhanced.hasPrefix("'") || enhanced.hasPrefix("`") {
                    enhanced = String(enhanced.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                while enhanced.hasSuffix("\"") || enhanced.hasSuffix("'") || enhanced.hasSuffix("`") {
                    enhanced = String(enhanced.dropLast()).trimmingCharacters(in: .whitespaces)
                }
                _ = quoteChars

                guard !enhanced.isEmpty else {
                    throw DraftCanvasError.rpcError(String(localized: "エンハンス結果が空でした"))
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let replacer = self.onReplacePromptText {
                        replacer(enhanced)
                    } else {
                        if let id = self.selectedProjectID {
                            self.inputsByProject[id]?.prompt = enhanced
                        } else {
                            self.draftInputs.prompt = enhanced
                        }
                    }
                    self.isEnhancingPrompt = false
                    self.logs.append("プロンプトエンハンス完了")
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isEnhancingPrompt = false
                    guard !(error is CancellationError) else {
                        self.logs.append("プロンプトエンハンス キャンセル")
                        return
                    }
                    self.errorToast = String(localized: "プロンプトエンハンスに失敗しました")
                    self.logs.append("プロンプトエンハンス失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    static func selectFastLowCostModel(from models: [CodexModel]) -> CodexModel {
        if let miniByID = models.first(where: { $0.id.hasSuffix("-mini") }) {
            return miniByID
        }
        let lightweightKeywords = ["mini", "haiku", "flash", "instant", "lite", "nano"]
        if let light = models.first(where: { model in
            let lower = model.displayName.lowercased() + " " + model.id.lowercased()
            return lightweightKeywords.contains(where: { lower.contains($0) })
        }) {
            return light
        }
        if let def = models.first(where: \.isDefault) { return def }
        return models[0]
    }
}
