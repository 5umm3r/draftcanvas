import XCTest
@testable import DraftCanvas

final class JSONRPCCodecTests: XCTestCase {
    func testEncodeRequestOmitsJSONRPCFieldForCodexAppServer() throws {
        let request = JSONRPCRequest(id: 7, method: "initialize", params: [
            "clientInfo": [
                "name": "draftcanvas",
                "title": "Draft Canvas",
                "version": "1.0"
            ],
            "capabilities": [
                "experimentalApi": true
            ]
        ])

        let data = try JSONRPCCodec.encodeRequest(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["jsonrpc"])
        XCTAssertEqual(object["id"] as? Int, 7)
        XCTAssertEqual(object["method"] as? String, "initialize")
        XCTAssertNotNil(object["params"])
    }

    func testLineParserEmitsCompleteMessagesOnly() throws {
        var parser = JSONLineParser()

        XCTAssertTrue(parser.append(Data("{\"id\":1".utf8)).isEmpty)
        let messages = parser.append(Data(",\"result\":{}}\n{\"method\":\"event\"}\n".utf8))

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["id"] as? Int, 1)
        XCTAssertEqual(messages[1]["method"] as? String, "event")
    }

    func testExtractsBase64ImageGenerationResult() throws {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
        let notification: [String: Any] = [
            "method": "rawResponseItem/completed",
            "params": [
                "item": [
                    "type": "image_generation_call",
                    "id": "img_1",
                    "status": "completed",
                    "result": pngHeader.base64EncodedString()
                ]
            ]
        ]

        let result = try XCTUnwrap(CodexEventExtractor.extractImageResult(from: notification))

        XCTAssertEqual(result.data, pngHeader)
        XCTAssertEqual(result.imageID, "img_1")
    }

    func testCodexLaunchUsesSiblingNodeWhenCodexIsNodeScript() throws {
        let codexPath = "/tmp/node-v/bin/codex"

        let configuration = CodexLaunchConfiguration.resolve(codexExecutablePath: codexPath)

        XCTAssertEqual(configuration.executablePath, "/tmp/node-v/bin/node")
        XCTAssertEqual(configuration.arguments, [codexPath, "app-server", "--listen", "stdio://"])
        XCTAssertTrue(configuration.environmentPath.hasPrefix("/tmp/node-v/bin:"))
    }

    func testParsesAccountAndUsageStatus() throws {
        let accountResponse: [String: Any] = [
            "account": [
                "type": "chatgpt",
                "email": "user@example.com",
                "planType": "plus"
            ],
            "requiresOpenaiAuth": true
        ]
        let rateLimitsResponse: [String: Any] = [
            "rateLimits": [
                "limitId": "codex",
                "primary": [
                    "usedPercent": 88,
                    "windowDurationMins": 300,
                    "resetsAt": 1_778_088_915
                ],
                "secondary": [
                    "usedPercent": 57,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_778_467_286
                ],
                "planType": "plus"
            ]
        ]

        let status = CodexAccountUsageStatus.parse(accountResponse: accountResponse, rateLimitsResponse: rateLimitsResponse)

        XCTAssertEqual(status.accountLabel, "user@example.com")
        XCTAssertEqual(status.planLabel, "plus")
        XCTAssertEqual(status.primaryUsageLabel, "5h 12%")
        XCTAssertEqual(status.secondaryUsageLabel, "weekly 43%")
        XCTAssertEqual(try XCTUnwrap(status.primaryUsageRemainingFraction), 0.12, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(status.secondaryUsageRemainingFraction), 0.43, accuracy: 0.001)
    }

    func testExtractAssistantTextIgnoresInputText() {
        let notification: [String: Any] = [
            "method": "rawResponseItem/completed",
            "params": [
                "item": [
                    "type": "message",
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "System instructions and user prompt echo..."]
                    ]
                ]
            ]
        ]
        XCTAssertNil(CodexEventExtractor.extractAssistantText(from: notification))
    }

    func testExtractAssistantTextCapturesOutputText() {
        let notification: [String: Any] = [
            "method": "rawResponseItem/completed",
            "params": [
                "item": [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": "Enhanced prompt text here."]
                    ]
                ]
            ]
        ]
        XCTAssertEqual(CodexEventExtractor.extractAssistantText(from: notification), "Enhanced prompt text here.")
    }

    func testExtractAssistantTextFiltersInputTextFromMixedContent() {
        let notification: [String: Any] = [
            "method": "rawResponseItem/completed",
            "params": [
                "item": [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        ["type": "input_text", "text": "should be ignored"],
                        ["type": "output_text", "text": "actual enhanced output"]
                    ]
                ]
            ]
        ]
        XCTAssertEqual(CodexEventExtractor.extractAssistantText(from: notification), "actual enhanced output")
    }

    func testProcessTerminationClosesHandlesWithoutResettingLaunchedStandardIO() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        ProcessTerminationResources.release(
            process: process,
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading
        )

        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
    }
}
