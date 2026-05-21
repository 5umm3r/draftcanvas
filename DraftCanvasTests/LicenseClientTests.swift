import XCTest
@testable import DraftCanvas

final class LicenseClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
        LicenseClient.urlSession = makeMockSession()
    }

    override func tearDown() {
        super.tearDown()
        LicenseClient.urlSession = .shared
        MockURLProtocol.handler = nil
    }

    // MARK: - activate

    func testActivate_success_returnsActivationID() async throws {
        let expectedID = "act_abc123"
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: ["id": expectedID])
            return (resp, data)
        }

        let result = try await LicenseClient.activate(key: "TEST-KEY")
        XCTAssertEqual(result, expectedID)
    }

    func testActivate_404_throwsInvalidKey() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        do {
            _ = try await LicenseClient.activate(key: "BAD-KEY")
            XCTFail("should throw")
        } catch LicenseError.invalidKey {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testActivate_limitError_throwsActivationLimitReached() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: ["detail": "activation limit reached"])
            return (resp, data)
        }

        do {
            _ = try await LicenseClient.activate(key: "LIMIT-KEY")
            XCTFail("should throw")
        } catch LicenseError.activationLimitReached {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - validate

    func testValidate_grantedStatus_returnsTrue() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "license_key": ["status": "granted"]
            ])
            return (resp, data)
        }

        let result = try await LicenseClient.validate(key: "KEY", instanceID: "ACT-ID")
        XCTAssertTrue(result)
    }

    func testValidate_revokedStatus_returnsFalse() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "license_key": ["status": "revoked"]
            ])
            return (resp, data)
        }

        let result = try await LicenseClient.validate(key: "KEY", instanceID: "ACT-ID")
        XCTAssertFalse(result)
    }

    func testValidate_networkError_throws() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await LicenseClient.validate(key: "KEY", instanceID: "ACT-ID")
            XCTFail("should throw")
        } catch LicenseError.network {
            // OK — ネットワークエラーは throw（誤って false = 失効扱いにしない）
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testValidate_requestBodyContainsActivationID() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.handler = { req in
            capturedBody = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: ["status": "granted"])
            return (resp, data)
        }

        _ = try await LicenseClient.validate(key: "MY-KEY", instanceID: "MY-ACT-ID")
        XCTAssertEqual(capturedBody?["key"] as? String, "MY-KEY")
        XCTAssertEqual(capturedBody?["activation_id"] as? String, "MY-ACT-ID")
    }
}

// MARK: - MockURLProtocol

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
