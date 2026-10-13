import Foundation

public struct MemoryExtraction: Codable, Sendable {
    public struct Person: Codable, Sendable { public var name: String; public var evidence: String }
    public struct Connection: Codable, Sendable { public var from: String; public var to: String; public var label: String; public var evidence: String }
    public var characters: [Person]
    public var relationships: [Connection]
    public static func decode(_ text: String) throws -> MemoryExtraction {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { throw FolioError.message("No structured story memory was returned.") }
        return try JSONDecoder().decode(Self.self, from: Data(text[start...end].utf8))
    }
    /// Every inferred item must cite an exact passage in the author's narration.
    /// It remains marked as inferred and can be edited or removed in the map.
    public func apply(to project: inout StoryProject, sceneID: UUID, narration: String) {
        func evidenced(_ quote: String) -> Bool { quote.count >= 3 && narration.localizedCaseInsensitiveContains(quote) }
        for person in characters.prefix(12) where evidenced(person.evidence) && !person.name.isEmpty && person.name.count < 60 {
            guard CharacterMatcher.mentions(StoryCharacter(name: person.name), in: person.evidence) else { continue }
            if !project.characters.contains(where: { CharacterMatcher.mentions($0, in: person.name) }) {
                project.characters.append(StoryCharacter(name: person.name))
            }
        }
        for connection in relationships.prefix(16) where evidenced(connection.evidence) && !connection.label.isEmpty && connection.label.count < 200 {
            let fromMatches = project.characters.filter { CharacterMatcher.mentions($0, in: connection.from) }
            let toMatches = project.characters.filter { CharacterMatcher.mentions($0, in: connection.to) }
            guard fromMatches.count == 1, toMatches.count == 1, let from = fromMatches.first, let to = toMatches.first, from.id != to.id,
                  CharacterMatcher.mentions(from, in: connection.evidence), CharacterMatcher.mentions(to, in: connection.evidence) else { continue }
            guard !project.relationships.contains(where: { (($0.from == from.id && $0.to == to.id) || ($0.from == to.id && $0.to == from.id)) && ($0.sourceSceneID == sceneID || $0.label.lowercased() == connection.label.lowercased()) }) else { continue }
            var relationship = Relationship(from: from.id, to: to.id, label: connection.label)
            relationship.evidence = connection.evidence; relationship.sourceSceneID = sceneID; relationship.inferred = true
            project.relationships.append(relationship)
        }
    }
}

public enum DraftEditing {
    public static func replacing(_ original: String, range: NSRange?, with replacement: String) throws -> String {
        guard let range, range.length > 0 else { return replacement }
        guard let swiftRange = Range(range, in: original) else { throw FolioError.message("The selected passage changed. Select it again before revising.") }
        var text = original; text.replaceSubrange(swiftRange, with: replacement); return text
    }
}

public extension MemoryExtraction {
    /// Exact linguistic patterns supplement the small model for common explicit
    /// kinship statements. No proximity-only relationship is ever invented.
    static func explicitConnections(in narration: String) -> MemoryExtraction {
        var people: [Person] = [], links: [Connection] = []
        let name = #"([\p{Lu}][\p{L}'’\-]+)"#
        let role = #"(father|mother|brother|sister|daughter|son|husband|wife|friend|mentor|boss|partner)"#
        let patterns: [(String, Int)] = [
            (name + #"\s+(?:meets|visits|calls|hugs|sees|greets|misses|joins|confronts)\s+(?:his|her|their)\s+"# + role + #"\s*,?\s*"# + name, 0),
            (name + #"[’']s\s+"# + role + #"\s*,?\s*"# + name, 0),
            (name + #"\s+is\s+"# + name + #"[’']s\s+"# + role, 1)
        ]
        for (pattern, layout) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: narration, range: NSRange(narration.startIndex..., in: narration)) {
                func group(_ index: Int) -> String { (narration as NSString).substring(with: match.range(at: index)) }
                let a = group(1), b = group(layout == 0 ? 3 : 2), relation = group(layout == 0 ? 2 : 3)
                let quote = group(0)
                let label = layout == 0 ? "\(b) is \(a)’s \(relation)" : "\(a) is \(b)’s \(relation)"
                people.append(Person(name: a, evidence: quote)); people.append(Person(name: b, evidence: quote))
                links.append(Connection(from: a, to: b, label: label, evidence: quote))
            }
        }
        // Resolve a pronoun only when one named person occurs before the explicit role.
        // More than one possible antecedent is left for the writer to clarify.
        if let kinship = try? NSRegularExpression(pattern: #"\b(?:his|her|their)\s+"# + role + #"\s+"# + name) {
            for match in kinship.matches(in: narration, range: NSRange(narration.startIndex..., in: narration)) {
                let start = max(0, match.range.location - 260)
                let before = (narration as NSString).substring(with: NSRange(location: start, length: match.range.location - start))
                let tagger = NSLinguisticTagger(tagSchemes: [.nameType], options: 0); tagger.string = before
                var candidates: [(String, NSRange)] = []
                tagger.enumerateTags(in: NSRange(before.startIndex..., in: before), scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range, _, _ in
                    if tag == .personalName { candidates.append(((before as NSString).substring(with: range), range)) }
                }
                let unique = Set(candidates.map { CharacterMatcher.normalized($0.0) })
                guard unique.count == 1, let candidate = candidates.last else { continue }
                let person = (narration as NSString).substring(with: match.range(at: 2))
                guard CharacterMatcher.normalized(candidate.0) != CharacterMatcher.normalized(person) else { continue }
                let quoteStart = start + candidate.1.location
                let quote = (narration as NSString).substring(with: NSRange(location: quoteStart, length: NSMaxRange(match.range) - quoteStart))
                let relation = (narration as NSString).substring(with: match.range(at: 1))
                people.append(Person(name: candidate.0, evidence: quote)); people.append(Person(name: person, evidence: quote))
                links.append(Connection(from: candidate.0, to: person, label: "\(person) is \(candidate.0)’s \(relation)", evidence: quote))
            }
        }
        return MemoryExtraction(characters: people, relationships: links)
    }
}
