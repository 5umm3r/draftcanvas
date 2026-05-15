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
            throw DraftCanvasError.invalidRequest(L("JSON-RPCリクエストをJSONとしてエンコードできません。"))
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

