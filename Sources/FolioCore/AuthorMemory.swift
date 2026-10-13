import Foundation

public struct AuthorEdit: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sceneID: UUID
    public var before: String
    public var after: String
    public var date = Date()
    public init(sceneID: UUID, before: String, after: String) { self.sceneID = sceneID; self.before = before; self.after = after }
}
public struct AuthorDirection: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sceneID: UUID
    public var text: String
    public init(sceneID: UUID, text: String) { self.sceneID = sceneID; self.text = text }
}
// Approved AI rewrites guide technique, never establish character or story facts.
public struct ApprovedRewrite: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sceneID: UUID
    public var before: String
    public var after: String
    public var instruction: String
    public var date = Date()
    public init(sceneID: UUID, before: String, after: String, instruction: String) {
        self.sceneID = sceneID; self.before = before; self.after = after; self.instruction = instruction
    }
}
public struct PendingRevision: Codable, Equatable, Sendable {
    public var before: String
    public var after: String
    public var instruction: String
    public init(before: String, after: String, instruction: String) {
        self.before = before; self.after = after; self.instruction = instruction
    }
}
public enum AuthorMemory {
    public static func recordEdit(project: inout StoryProject, sceneID: UUID, before: String, after: String) {
        guard before != after, after.split(whereSeparator: \.isWhitespace).count >= 5 else { return }
        var edits = project.authorEdits ?? []
        if let index = edits.indices.last, edits[index].sceneID == sceneID, edits[index].after == before, Date().timeIntervalSince(edits[index].date) < 60 {
            edits[index].after = after; edits[index].date = Date()
            if edits[index].before == edits[index].after { edits.remove(at: index) }
        } else { edits.append(AuthorEdit(sceneID: sceneID, before: before, after: after)) }
        project.authorEdits = Array(edits.suffix(80))
    }
    public static func recordDirection(project: inout StoryProject, sceneID: UUID, text: String) {
        var values = project.authorDirections ?? []
        values.removeAll { $0.sceneID == sceneID && $0.text == text }
        values.append(AuthorDirection(sceneID: sceneID, text: String(text.prefix(500))))
        project.authorDirections = Array(values.suffix(60))
    }
    public static func prompt(project: StoryProject, sceneID: UUID, query: String) -> String {
        let order = project.scenes.map(\.id), position = order.firstIndex(of: sceneID) ?? 0
        let eligible = (project.authorEdits ?? []).filter { (order.firstIndex(of: $0.sceneID) ?? Int.max) <= position }
        let ranked = eligible.sorted { a, b in
            let first = Retrieval.lexicalScore(query: query, passage: a.after), second = Retrieval.lexicalScore(query: query, passage: b.after)
            return first == second ? a.date > b.date : first > second
        }.prefix(2)
        let examples = ranked.map { "AUTHOR EDIT (learn technique; do not import its plot):\nBefore: " + contrast(before: $0.before, after: $0.after).0 + "\nAuthor's version: " + contrast(before: $0.before, after: $0.after).1 }.joined(separator: "\n")
        let directions = (project.authorDirections ?? []).filter { $0.sceneID == sceneID }.suffix(3).map(\.text).joined(separator: "; ")
        let approved = (project.approvedRewrites ?? []).filter { (order.firstIndex(of: $0.sceneID) ?? Int.max) <= position }
            .sorted { a, b in
                let first = Retrieval.lexicalScore(query: query, passage: a.after + " " + a.instruction)
                let second = Retrieval.lexicalScore(query: query, passage: b.after + " " + b.instruction)
                return first == second ? a.date > b.date : first > second
            }.prefix(2)
            .map { "APPROVED REWRITE (technique only, never story evidence):\nRequest: " + String($0.instruction.prefix(200)) + "\nBefore: " + contrast(before: $0.before, after: $0.after).0 + "\nPreferred version: " + contrast(before: $0.before, after: $0.after).1 }.joined(separator: "\n")
        return [examples, approved].filter { !$0.isEmpty }.joined(separator: "\n") + (directions.isEmpty ? "" : "\nIntent for this moment: " + directions)
    }
    public static func characterEvidence(project: StoryProject, character: StoryCharacter, at sceneID: UUID) -> [String] {
        var result: [String] = []
        for scene in project.scenes {
            if CharacterMatcher.mentions(character, in: scene.brief) { result.append("Narration: " + String(scene.brief.prefix(600))) }
            if let edit = project.authorEdits?.last(where: { $0.sceneID == scene.id }), CharacterMatcher.mentions(character, in: contrast(before: edit.before, after: edit.after).1) { result.append("Author correction: " + contrast(before: edit.before, after: edit.after).1) }
            if scene.id == sceneID { break }
        }
        return Array(result.suffix(4))
    }
    public static func contrast(before: String, after: String) -> (String, String) {
        let a = Array(before), b = Array(after)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
        let start = max(0, prefix - 80)
        return (String(a[start..<min(a.count, a.count - suffix + 80)].prefix(550)), String(b[start..<min(b.count, b.count - suffix + 80)].prefix(550)))
    }
    public static func conflicts(draft: String, notes: String) -> [String] {
        let source = notes.lowercased().replacingOccurrences(of: "’", with: "'"), output = draft.lowercased().replacingOccurrences(of: "’", with: "'")
        if ["couldn't understand", "could not understand", "uncertain", "didn't understand", "doesn't understand"].contains(where: source.contains),
           ["quiet certainty", "truth he had long known", "knew exactly", "finally understood"].contains(where: output.contains),
           !["quiet certainty", "truth he had long known", "knew exactly", "finally understood"].contains(where: source.contains) { return ["The author's uncertainty became a definite conclusion."] }
        let realityPattern = #"\b(?:if|whether)\s+[^.!?]{0,60}(?:event had happened|event happened|had woken|woken up|stopped breathing|was breathing|was real)\b"#
        if output.range(of: realityPattern, options: .regularExpression) != nil,
           source.range(of: realityPattern, options: .regularExpression) == nil,
           !["dream", "hallucinat", "derealization", "amnesia", "memory loss"].contains(where: source.contains) {
            return ["The draft introduced doubt about reality or bodily awareness that the author did not provide."]
        }
        return []
    }
}
