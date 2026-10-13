import XCTest
import Foundation
@testable import FolioApp

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class TransportTests: XCTestCase {
    @MainActor private func engine(_ response: String, status: Int = 200) -> LocalEngines {
        StubProtocol.status = status; StubProtocol.body = Data(response.utf8)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let engines = LocalEngines(session: URLSession(configuration: config)); engines.ready = true
        return engines
    }
    @MainActor func testWriterReadsCompleteResponseThroughHTTPTransport() async throws {
        let engine = engine("data: {\"choices\":[{\"delta\":{\"content\":\"A finished sentence.\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        let text = try await engine.complete(system: "Write", user: "Notes") { _ in }
        XCTAssertEqual(text, "A finished sentence.")
    }
    @MainActor func testInterruptedHTTPResponseCannotBecomeDraft() async {
        let engine = engine("data: {\"choices\":[{\"delta\":{\"content\":\"A partial sentence\"}}]}\n\n")
        do { _ = try await engine.complete(system: "Write", user: "Notes") { _ in }; XCTFail("Accepted partial response") } catch {}
    }
    @MainActor func testServerErrorIsReported() async {
        let engine = engine("Unauthorized", status: 401)
        do { _ = try await engine.complete(system: "Write", user: "Notes") { _ in }; XCTFail("Accepted unauthorized response") } catch {}
    }
    @MainActor func testInvalidEmbeddingIsRejected() async {
        let engine = engine("{\"data\":[{\"embedding\":[]}]}")
        do { _ = try await engine.embed("Idea"); XCTFail("Accepted empty embedding") } catch {}
    }
    @MainActor func testMalformedTranscriptionIsReported() async {
        let engine = engine("{\"message\":\"Invalid audio\"}")
        do { _ = try await engine.transcribe(wav: Data(), names: []); XCTFail("Accepted invalid transcript") } catch {}
    }
    @MainActor func testModifiedModelIsVerifiedBeforeLaunching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let specs = ["writer", "embedding", "speech"].map { ModelSpec(id: $0, name: $0, file: $0 + ".bin", url: "https://example.invalid/model", sha256: String(repeating: "0", count: 64), bytes: 3, license: "Test") }
        try JSONEncoder().encode(specs).write(to: root.appendingPathComponent("models.json"))
        for spec in specs { try Data([1,2,3]).write(to: root.appendingPathComponent(spec.file)) }
        let engine = LocalEngines(modelDirectory: root, resourceDirectory: root, runtimeDirectory: root)
        XCTAssertTrue(engine.installed)
        await engine.prepare()
        XCTAssertFalse(engine.ready)
        XCTAssertEqual(engine.modelStatus["writer"], false)
        XCTAssertTrue(engine.error?.contains("integrity") == true)
    }
}
