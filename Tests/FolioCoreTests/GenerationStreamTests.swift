import XCTest
@testable import FolioCore

final class GenerationStreamTests: XCTestCase {
    func testCompleteUnicodeStream() throws {
        var stream = GenerationStream()
        try stream.consume("data: {\"choices\":[{\"delta\":{\"content\":\"Joseph’s silence. 🌒\"},\"finish_reason\":null}]}")
        try stream.consume("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
        try stream.consume("data: [DONE]")
        XCTAssertEqual(try stream.result(), "Joseph’s silence. 🌒")
    }
    func testInterruptedAndTruncatedResponsesAreWithheld() throws {
        var stream = GenerationStream()
        try stream.consume("data: {\"choices\":[{\"delta\":{\"content\":\"An unfinished\"}}]}")
        XCTAssertThrowsError(try stream.result())
        XCTAssertThrowsError(try stream.consume("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}"))
        XCTAssertThrowsError(try stream.consume("data: {\"error\":{\"message\":\"failure\"}}"))
        XCTAssertThrowsError(try stream.consume("data: garbage"))
    }
    func testDoneWithoutSuccessAndEmptyResultAreRejected() throws {
        var stream = GenerationStream(); try stream.consume("data: [DONE]")
        XCTAssertThrowsError(try stream.result())
        var empty = GenerationStream()
        try empty.consume("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
        try empty.consume("data: [DONE]")
        XCTAssertThrowsError(try empty.result())
    }
}
