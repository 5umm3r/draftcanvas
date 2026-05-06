import XCTest
@testable import ImageCreator

final class JSONRPCCodecTests: XCTestCase {
    func testEncodeRequestOmitsJSONRPCFieldForCodexAppServer() throws {
        let request = JSONRPCRequest(id: 7, method: "initialize", params: [
            "clientInfo": [
                "name": "image-creator",
                "title": "Image Creator",
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

    func testExtractsSVGFromAssistantText() throws {
        let text = "Here is the SVG:\n<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"10\"/></svg>"

        let svg = try XCTUnwrap(SVGExtractor.extract(from: text))

        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.hasSuffix("</svg>"))
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
        XCTAssertEqual(status.primaryUsageLabel, "5h 88%")
        XCTAssertEqual(status.secondaryUsageLabel, "weekly 57%")
    }
}
