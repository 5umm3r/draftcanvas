import Foundation

struct JSONRPCRequest {
    let id: Int
    let method: String
    let params: [String: Any]?

    init(id: Int, method: String, params: [String: Any]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

enum JSONRPCCodec {
    static func encodeRequest(_ request: JSONRPCRequest) throws -> Data {
        var object: [String: Any] = [
            "id": request.id,
            "method": request.method
        ]
        if let params = request.params {
            object["params"] = params
        }

        guard JSONSerialization.isValidJSONObject(object) else {
            throw DraftCanvasError.invalidRequest(String(localized: "JSON-RPCリクエストをJSONとしてエンコードできません。"))
        }

        return try JSONSerialization.data(withJSONObject: object, options: [])
    }

    static func encodeRequestLine(_ request: JSONRPCRequest) throws -> Data {
        var data = try encodeRequest(request)
        data.append(0x0A)
        return data
    }
}

struct JSONLineParser {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [[String: Any]] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var messages: [[String: Any]] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)

            guard !lineData.isEmpty else { continue }
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(lineData)),
                let dictionary = object as? [String: Any]
            else {
                continue
            }
            messages.append(dictionary)
        }
        return messages
    }
}

enum CodexEventExtractor {
    static func extractImageResult(from message: [String: Any]) -> CodexImageResult? {
        guard
            message["method"] as? String == "rawResponseItem/completed",
            let params = message["params"] as? [String: Any],
            let item = params["item"] as? [String: Any],
            item["type"] as? String == "image_generation_call",
            let result = item["result"] as? String,
            let data = decodeImageResult(result)
        else {
            return nil
        }

        return CodexImageResult(
            imageID: item["id"] as? String ?? UUID().uuidString,
            data: data,
            revisedPrompt: item["revised_prompt"] as? String
        )
    }

    static func extractAssistantText(from message: [String: Any]) -> String? {
        guard
            message["method"] as? String == "rawResponseItem/completed",
            let params = message["params"] as? [String: Any],
            let item = params["item"] as? [String: Any],
            item["type"] as? String == "message",
            item["role"] as? String != "user",
            let content = item["content"] as? [[String: Any]]
        else {
            return nil
        }

        let chunks = content.compactMap { part -> String? in
            guard part["type"] as? String == "output_text" else { return nil }
            return part["text"] as? String
        }
        return chunks.isEmpty ? nil : chunks.joined(separator: "\n")
    }

    static func isTurnCompleted(_ message: [String: Any], threadID: String) -> Bool {
        guard
            message["method"] as? String == "turn/completed",
            let params = message["params"] as? [String: Any]
        else {
            return false
        }
        return params["threadId"] as? String == threadID
    }

    static func threadID(from message: [String: Any]) -> String? {
        guard let params = message["params"] as? [String: Any] else {
            return nil
        }
        return params["threadId"] as? String
    }

    private static func decodeImageResult(_ result: String) -> Data? {
        if let comma = result.firstIndex(of: ","), result[..<comma].contains("base64") {
            return Data(base64Encoded: String(result[result.index(after: comma)...]))
        }
        return Data(base64Encoded: result)
    }
}

enum CodexLogFormatter {
    static let defaultThreadInstructions = """
    You are Draft Canvas's focused image-generation helper.
    Use the current request and provided localImage attachments only.
    Do not inspect unrelated local files, list directories, search the filesystem, or run shell commands unless the user explicitly asks for that in the current request.
    Return only the requested image generation result or prompt text; avoid implementation commentary.
    """

    static func outbound(method: String, params: [String: Any]?) -> String {
        switch method {
        case "thread/start":
            let model = params?["model"] as? String
            let config = params?["config"] as? [String: Any]
            let effort = config?["model_reasoning_effort"] as? String
            return ["-> thread/start", model.map { "model=\($0)" }, effort.map { "reasoning=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
        case "turn/start":
            let thread = params?["threadId"] as? String
            let inputCount = (params?["input"] as? [[String: Any]])?.count
            return ["-> turn/start", thread.map { "thread=\($0)" }, inputCount.map { "input=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
        default:
            return "-> \(method)"
        }
    }

    static func inbound(_ message: [String: Any]) -> String? {
        if let error = message["error"] as? [String: Any] {
            let rawMessage = error["message"] as? String ?? "unknown error"
            return "<- error: \(shorten(rawMessage, maxLength: 180))"
        }

        guard let method = message["method"] as? String else {
            return nil
        }

        switch method {
        case "rawResponseItem/completed":
            return rawResponseItemSummary(message)
        case "turn/completed":
            return "<- Codex turn が完了しました。"
        case "account/rateLimits/updated":
            return "<- Codex使用量を受信しました。"
        default:
            return nil
        }
    }

    private static func rawResponseItemSummary(_ message: [String: Any]) -> String? {
        guard
            let params = message["params"] as? [String: Any],
            let item = params["item"] as? [String: Any],
            let type = item["type"] as? String
        else {
            return nil
        }

        switch type {
        case "image_generation_call":
            let id = item["id"] as? String ?? "unknown"
            return "<- 画像生成結果を受信しました: \(id)"
        case "message":
            guard item["role"] as? String == "assistant" else { return nil }
            return "<- assistant応答を受信しました。"
        default:
            return nil
        }
    }

    private static func shorten(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "..."
    }
}
