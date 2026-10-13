import Foundation

public struct StoryCharacter: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var aliases: [String] = []
    public var details: String = ""
    public var traits: [CharacterTrait]? = nil
    public var avatar: Data? = nil
    public var developments: [Development] = []
    public init(name: String = "", details: String = "") { self.name = name; self.details = details }
}
public struct Development: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var sceneID: UUID
    public var note: String
    public init(sceneID: UUID, note: String) { self.sceneID = sceneID; self.note = note }
}
public struct Relationship: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var from: UUID
    public var to: UUID
    public var label: String
    public var evidence: String? = nil
    public var sourceSceneID: UUID? = nil
    public var inferred: Bool? = nil
    public init(from: UUID, to: UUID, label: String) { self.from = from; self.to = to; self.label = label }
}
public struct WritingTurn: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: String
    public var text: String
    public var date = Date()
    public init(kind: String, text: String) { self.kind = kind; self.text = text }
}
public struct Scene: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var title: String = "Untitled scene"
    public var brief: String = ""
    public var text: String = ""
    public var characterIDs: [UUID] = []
    public var pendingDraft: String? = nil
    public var conversation: [WritingTurn]? = nil
    public var continuation: String? = nil
    public var pendingFeedback: String? = nil
    public var pendingRevision: PendingRevision? = nil
    public init(title: String = "Untitled scene") { self.title = title }
}
public struct Chapter: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var title: String = "Chapter 1"
    public var scenes: [Scene] = [Scene()]
    public var finished: Bool? = nil
    public init(title: String = "Chapter 1") { self.title = title }
}
public struct Source: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var text: String
    public var isStyleSample: Bool = true
    public var analysis: StyleAnalysis? = nil
    public var use: SourceUse? = nil
    public var continued: Bool? = nil
    public var effectiveUse: SourceUse { use ?? (isStyleSample ? .style : .reference) }
    public init(name: String, text: String) { self.name = name; self.text = text }
}
public struct StoryProject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String = "Untitled story"
    public var mode: WritingMode? = nil
    public var audience: String? = nil
    public var writingMode: WritingMode { mode ?? .book }
    public var premise: String = ""
    public var style: String = ""
    public var preferences: [String] = []
    public var bookTypography: BookTypography? = nil
    public var authorEdits: [AuthorEdit]? = nil
    public var authorDirections: [AuthorDirection]? = nil
    public var approvedRewrites: [ApprovedRewrite]? = nil
    public var chapters: [Chapter] = [Chapter()]
    public var characters: [StoryCharacter] = []
    public var relationships: [Relationship] = []
    public var sources: [Source] = []
    public var assistantAvatar: Data? = nil
    public var updatedAt: Date = Date()
    public var schemaVersion: Int = 1
    public init(name: String = "Untitled story") { self.name = name }
    public var scenes: [Scene] { chapters.flatMap(\.scenes) }
    public var wordCount: Int { scenes.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
    public func characterContext(at sceneID: UUID, mentions: String) -> String {
        let ordered = scenes.map(\.id)
        let position = ordered.firstIndex(of: sceneID) ?? 0
        let selected = scenes.first(where: { $0.id == sceneID })?.characterIDs ?? []
        return characters.filter { selected.contains($0.id) || CharacterMatcher.mentions($0, in: mentions) }.map { character in
            let active = character.developments.filter { (ordered.firstIndex(of: $0.sceneID) ?? Int.max) <= position }
            return "\(character.name): \(character.details)" + AuthorMemory.characterEvidence(project: self, character: character, at: sceneID).map { "\nAuthor evidence: " + $0 }.joined() + (character.traits ?? []).filter { !$0.value.isEmpty }.map { "\n\($0.category): \($0.value)" }.joined() + active.map { "\nDevelopment: \($0.note)" }.joined()
        }.joined(separator: "\n\n")
    }
    public func markdown() -> String {
        "# \(name)\n\n" + chapters.map { chapter in
            "## \(chapter.title)\n\n" + chapter.scenes.map { "\($0.text)" }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }.joined(separator: "\n\n") + "\n"
    }
    public func validate() throws {
        guard schemaVersion == 1, !chapters.isEmpty, chapters.allSatisfy({ !$0.scenes.isEmpty }) else { throw FolioError.invalidProject }
        let identifiers = chapters.map(\.id) + scenes.map(\.id) + characters.map(\.id) + sources.map(\.id) + relationships.map(\.id)
        guard Set(identifiers).count == identifiers.count else { throw FolioError.invalidProject }
        let ids = Set(characters.map(\.id)), sceneIDs = Set(scenes.map(\.id))
        guard relationships.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to && ($0.sourceSceneID == nil || sceneIDs.contains($0.sourceSceneID!)) }),
              scenes.allSatisfy({ Set($0.characterIDs).isSubset(of: ids) }),
              characters.allSatisfy({ $0.developments.allSatisfy { sceneIDs.contains($0.sceneID) } }) else { throw FolioError.invalidProject }
    }
}
public enum FolioError: LocalizedError {
    case invalidProject, database(String), message(String)
    public var errorDescription: String? {
        switch self {
        case .invalidProject: return "This project is incomplete or uses an unsupported format. The original file has not been changed."
        case .database(let message), .message(let message): return message
        }
    }
}
public enum CharacterMatcher {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func mentions(_ character: StoryCharacter, in text: String) -> Bool {
        let input = normalized(text)
        return ([character.name] + character.aliases).filter { !$0.isEmpty }.contains { name in
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: normalized(name)) + "(?![\\p{L}\\p{N}])"
            return input.range(of: pattern, options: .regularExpression) != nil
        }
    }
    public static func suggestions(for name: String, in characters: [StoryCharacter]) -> [StoryCharacter] {
        let needle = normalized(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return characters }
        return characters.filter { character in
            ([character.name] + character.aliases).contains { candidate in
                let value = normalized(candidate)
                return value.contains(needle) || distance(needle, value) <= (needle.count > 5 ? 2 : 1)
            }
        }
    }
    public static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, cb) in b.enumerated() { current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (ca == cb ? 0 : 1)) }
            previous = current
        }
        return previous[b.count]
    }
    public static func canonicalize(_ text: String, characters: [StoryCharacter]) -> String {
        var output = text
        var owners: [String: Set<UUID>] = [:]
        for c in characters { for n in [c.name] + c.aliases { owners[normalized(n), default: []].insert(c.id) } }
        for character in characters {
            for alias in character.aliases.sorted(by: { $0.count > $1.count }) where !alias.isEmpty && owners[normalized(alias)]?.count == 1 {
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: alias) + "(?![\\p{L}\\p{N}])"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    output = regex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: NSRegularExpression.escapedTemplate(for: character.name))
                }
            }
        }
        return output
    }
}
public enum VoiceCommand: Equatable, Sendable {
    case chapter(String), character(String), scene(String), rewrite(String), dictation(String)
    public static func parse(_ input: String) -> VoiceCommand {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        if ["finish chapter", "end chapter", "finish this chapter", "end this chapter", "chapter finished"].contains(lower) { return .chapter("") }
        for prefix in ["start chapter ", "/chapter ", "new chapter "] where lower.hasPrefix(prefix) {
            return .chapter("Chapter " + String(text.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: ".!?")))
        }
        if lower == "/character" { return .character("") }
        if lower.hasPrefix("/character ") { return .character(String(text.dropFirst(11))) }
        if lower.hasPrefix("#scene ") { return .scene(String(text.dropFirst(7))) }
        if lower == "#scene" || lower == "new scene" { return .scene("") }
        if ["tone down", "tone it down", "less description", "make it shorter", "more depth"].contains(lower) { return .rewrite(lower) }
        return .dictation(text)
    }
}
public struct Passage: Codable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var text: String
    public var isStyle: Bool
    public init(id: String, label: String, text: String, isStyle: Bool) { self.id = id; self.label = label; self.text = text; self.isStyle = isStyle }
}
public enum Retrieval {
    public static func passages(project: StoryProject, before sceneID: UUID) -> [Passage] {
        var result: [Passage] = []
        for source in project.sources {
            for (index, chunk) in chunks(source.text).enumerated() {
                result.append(Passage(id: "source-\(source.id)-\(index)", label: source.name, text: chunk, isStyle: source.isStyleSample))
            }
        }
        for scene in project.scenes {
            if scene.id == sceneID { break }
            for (index, chunk) in chunks(scene.text).enumerated() {
                result.append(Passage(id: "scene-\(scene.id)-\(index)", label: scene.title, text: chunk, isStyle: false))
            }
        }
        return result
    }
    public static func chunks(_ text: String, words: Int = 160) -> [String] {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return [] }
        return stride(from: 0, to: tokens.count, by: words).map { tokens[$0..<min($0 + words, tokens.count)].joined(separator: " ") }
    }
    public static func lexicalScore(query: String, passage: String) -> Double {
        let queryTokens = Set(CharacterMatcher.normalized(query).split { !$0.isLetter && !$0.isNumber }.map(String.init)).filter { $0.count > 2 }
        let tokens = Set(CharacterMatcher.normalized(passage).split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return queryTokens.isEmpty ? 0 : Double(queryTokens.intersection(tokens).count) / Double(queryTokens.count)
    }
    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Double = 0, a: Double = 0, b: Double = 0
        for (x, y) in zip(lhs, rhs) { dot += Double(x) * Double(y); a += Double(x) * Double(x); b += Double(y) * Double(y) }
        return a > 0 && b > 0 ? dot / sqrt(a * b) : 0
    }
}
