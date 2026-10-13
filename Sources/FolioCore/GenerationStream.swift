import Foundation

/// Accepts only a complete, successful OpenAI-compatible SSE response.
public struct GenerationStream {
    public private(set) var text = ""
    public private(set) var finished = false
    public private(set) var done = false
    public init() {}
    public mutating func consume(_ line: String) throws {
        guard line.hasPrefix("data:") else { return }
        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if raw == "[DONE]" { done = true; return }
        guard let data = raw.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FolioError.message("The writing engine sent an unreadable response. Your notes are saved; try again.") }
        if let failure = event["error"] as? [String: Any] {
            let detail = (failure["message"] as? String).map { String($0.prefix(200)) } ?? "Unknown engine error"
            throw FolioError.message("The writing engine stopped before finishing: " + detail + ". Your notes are saved; try again.")
        }
        guard let choices = event["choices"] as? [[String: Any]], let choice = choices.first else { return }
        if let content = (choice["delta"] as? [String: Any])?["content"] as? String { text += content }
        if let reason = choice["finish_reason"] as? String {
            guard reason == "stop" else { throw FolioError.message("The draft exceeded the local writing limit before it finished. Split the idea into shorter passages and try again.") }
            finished = true
        }
    }
    public func result() throws -> String {
        guard done && finished else { throw FolioError.message("The writing connection ended before the draft was complete. Your notes are saved; try again.") }
        let clean = PromptBuilder.cleanTranscript(text)
        guard !clean.isEmpty else { throw FolioError.message("The model returned an empty draft. Please try again.") }
        return clean
    }
}
