import Foundation

public struct WritingMatch: Identifiable, Sendable {
    public let id: String
    public let projectID: UUID
    public let sceneID: UUID?
    public let characterName: String?
    public let kind: String
    public let title: String
    public let excerpt: String
}
public enum LibrarySearch {
    public static func find(_ query: String, projects: [StoryProject]) -> [WritingMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [WritingMatch] = []
        func add(_ p: StoryProject, id: UUID, scene: UUID? = nil, character: String? = nil, kind: String, title: String, text: String) {
            guard (title + " " + text).localizedCaseInsensitiveContains(query) else { return }
            let start = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound ?? text.startIndex
            let excerpt = String(text[start...].prefix(180)).replacingOccurrences(of: "\n", with: " ")
            results.append(WritingMatch(id: p.id.uuidString + kind + id.uuidString, projectID: p.id, sceneID: scene, characterName: character, kind: kind, title: p.name + " · " + title, excerpt: excerpt))
        }
        for p in projects.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            add(p, id: p.id, kind: "Project", title: p.name, text: p.premise)
            for chapter in p.chapters { for scene in chapter.scenes {
                add(p, id: scene.id, scene: scene.id, kind: "Writing", title: chapter.title, text: [scene.text, scene.pendingDraft ?? "", scene.brief, scene.continuation ?? "", (scene.conversation ?? []).map(\.text).joined(separator: "\n")].joined(separator: "\n"))
            } }
            for c in p.characters { add(p, id: c.id, character: c.name, kind: "Character", title: c.name, text: ([c.details, c.aliases.joined(separator: " ")] + (c.traits ?? []).map(\.value) + c.developments.map(\.note)).joined(separator: " ")) }
            for source in p.sources { add(p, id: source.id, kind: "Source", title: source.name, text: source.text) }
        }
        return Array(results.prefix(80))
    }
}
