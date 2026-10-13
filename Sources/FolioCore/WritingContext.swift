import Foundation

public enum WritingMode: String, Codable, CaseIterable, Sendable {
    case book, blog, social, technical
    public var title: String { switch self { case .book: "Book"; case .blog: "Blog"; case .social: "X post"; case .technical: "Technical paper" } }
    public var icon: String { switch self { case .book: "book.closed"; case .blog: "doc.text"; case .social: "quote.bubble"; case .technical: "doc.text.magnifyingglass" } }
    public var guidance: String {
        switch self {
        case .book: "Write narrative prose. Preserve the people, relationships, events and chronological order in the author’s notes. Elaborate inner experience, not new events."
        case .blog: "Write a readable blog draft based on the author’s points. Use useful headings where appropriate. Preserve their claims and examples; invent no facts, statistics or quotations."
        case .social: "Write one concise X post, with the author's meaning and voice. No invented claims, hashtags or calls to action. Return only the post."
        case .technical: "Write a technical draft from supplied claims and evidence. Use precise language and section headings when useful. Do not invent data, results, methods, citations or references. Mark missing evidence as [evidence needed]."
        }
    }
    public var placeholder: String { switch self { case .book: "Describe what happens, what changes, and how it feels…"; case .blog: "What do you want to explain? Give your points and examples…"; case .social: "What do you want to say? Give the idea in your own words…"; case .technical: "Describe the claim, method, evidence, and limitations…" } }
}
public enum SourceUse: String, Codable, CaseIterable, Sendable {
    case continuation, reference, style
    public var title: String { switch self { case .continuation: "Continue from here"; case .reference: "Reference material"; case .style: "My writing style" } }
    public var explanation: String { switch self { case .continuation: "Add this text to the manuscript and start writing after it. Also learn its voice."; case .reference: "Use its facts as context. Keep it outside the manuscript."; case .style: "Learn how you write. Keep its events and characters out of this story." } }
}
public enum StoryContext {
    public static func priorScenes(_ project: StoryProject, before id: UUID) -> [Scene] { Array(project.scenes.prefix { $0.id != id }) }
    public static func continuity(_ project: StoryProject, before id: UUID) -> String {
        let prior = priorScenes(project, before: id)
        // Author narration is retained as factual memory; accepted prose supplies the continuation.
        let notes = prior.suffix(4).filter { !$0.brief.isEmpty }.map { $0.brief }.joined(separator: "\n")
        let prose = prior.suffix(3).map(\.text).joined(separator: "\n\n")
        return "PRIOR AUTHOR NOTES:\n" + String(notes.suffix(1800)) + "\nLAST ACCEPTED WRITING:\n" + String(prose.suffix(1800))
    }
    public static func facts(project: StoryProject, scene: Scene) -> String {
        let active = project.characterContext(at: scene.id, mentions: scene.brief + " " + scene.text)
        let names = project.characters.filter { CharacterMatcher.mentions($0, in: scene.brief) }.map(\.id)
        let position = project.scenes.firstIndex { $0.id == scene.id } ?? 0
        let links = project.relationships.filter { edge in
            (names.contains(edge.from) || names.contains(edge.to)) && (edge.sourceSceneID == nil || (project.scenes.firstIndex { $0.id == edge.sourceSceneID } ?? Int.max) <= position)
        }.compactMap { edge -> String? in
            guard let from = project.characters.first(where: { $0.id == edge.from }), let to = project.characters.first(where: { $0.id == edge.to }) else { return nil }
            return "\(from.name) → \(to.name): \(edge.label)"
        }.joined(separator: "\n")
        return String((active + "\n" + links).prefix(1600))
    }
    public static func continueSource(_ source: Source, in project: inout StoryProject) {
        var chapter = Chapter(title: source.name.replacingOccurrences(of: ".txt", with: "").replacingOccurrences(of: ".md", with: ""))
        chapter.scenes[0].text = source.text; chapter.scenes[0].title = "Imported manuscript"; chapter.finished = project.writingMode == .book
        if project.writingMode == .book {
            if project.chapters.count == 1 && project.scenes.allSatisfy({ $0.text.isEmpty && $0.brief.isEmpty && $0.pendingDraft == nil }) {
                // Keep the initial identifiers so existing developments remain valid.
                project.chapters[0].title = chapter.title; project.chapters[0].finished = true
                project.chapters[0].scenes[0].text = source.text; project.chapters[0].scenes[0].title = "Imported manuscript"
            }
            else { project.chapters.append(chapter) }
            project.chapters.append(Chapter(title: "In progress"))
        } else {
            if project.scenes.allSatisfy({ $0.text.isEmpty && $0.brief.isEmpty && $0.pendingDraft == nil }) { project.chapters = [chapter] }
            else { project.chapters[project.chapters.count - 1].scenes.append(chapter.scenes[0]) }
            project.chapters[project.chapters.count - 1].scenes.append(Scene(title: "Continue writing"))
        }
    }
}
public struct GroundingVerdict: Codable, Sendable {
    public var faithful: Bool
    public var reason: String
}
public enum GroundingCheck {
    public static func safeCopyEdit(_ draft: String, notes: String, context: String) -> Bool {
        guard issues(draft: draft, narration: notes, context: context).isEmpty else { return false }
        func tokens(_ text: String) -> Set<String> { Set(CharacterMatcher.normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)) }
        let a = tokens(notes), b = tokens(draft)
        guard !a.isEmpty, Double(a.intersection(b).count) / Double(a.count) >= 0.65 else { return false }
        let negations = ["not", "never", "doesn't", "didn't", "couldn't", "can't", "cannot", "don't", "won't"]
        if negations.contains(where: { notes.lowercased().contains($0) }) && !negations.contains(where: { draft.lowercased().contains($0) }) { return false }
        return true
    }
    public static func literalDescription(_ text: String) -> String {
        // Similes describe experience; they do not establish a literal room, door or object.
        text.replacingOccurrences(of: #"(?i)\b(?:like|as if|as though)\s+[^.!?]*(?=[.!?]|$)"#, with: "", options: .regularExpression)
    }
    public static func issues(draft: String, narration: String, context: String, strictScene: Bool = true, requireCoverage: Bool = true) -> [String] {
        var issues: [String] = []
        let allowed = CharacterMatcher.normalized(narration + " " + context)
        let result = CharacterMatcher.normalized(draft)
        // Concrete scene replacements seen in regressions. Only reject when unsupported by story facts.
        for term in ["steering wheel", "spaceship", "four people", "smiling at the fire", "gunshot", "wedding ceremony", "hospital bed"] where result.contains(term) && !allowed.contains(term) { issues.append("Unsupported scene detail: " + term) }
        if requireCoverage && narration.lowercased().contains("anniversary") && !result.contains("anniversary") { issues.append("Missing the anniversary event.") }
        if requireCoverage && narration.lowercased().contains("death anniversary") && !(result.contains("death") || result.contains("died") || result.contains("passed away") || result.contains("loss")) { issues.append("Missing the mother's death.") }
        for assertion in ["didn't feel anything", "did not feel anything", "felt nothing", "no longer angry", "no longer uncertain"] where result.contains(assertion) && !allowed.contains(assertion) { issues.append("Unsupported emotional conclusion: " + assertion) }
        let tagger = NSLinguisticTagger(tagSchemes: [.nameType], options: 0)
        func people(_ text: String) -> Set<String> {
            tagger.string = text
            var names = Set<String>()
            tagger.enumerateTags(in: NSRange(text.startIndex..., in: text), scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range, _, _ in
                if tag == .personalName, let r = Range(range, in: text) { names.insert(CharacterMatcher.normalized(String(text[r]))) }
            }
            return names
        }
        if strictScene {
            let language = NSLinguisticTagger(tagSchemes: [.lexicalClass, .lemma], options: 0)
            func nouns(_ text: String) -> Set<String> {
                language.string = text
                var nouns = Set<String>()
                language.enumerateTags(in: NSRange(text.startIndex..., in: text), scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range, _, _ in
                    if tag == .noun, let r = Range(range, in: text) {
                        let lemma = language.tag(at: range.location, scheme: .lemma, tokenRange: nil, sentenceRange: nil)?.rawValue ?? String(text[r])
                        nouns.insert(CharacterMatcher.normalized(lemma))
                    }
                }
                return nouns
            }
            let abstract: Set<String> = ["thought", "feeling", "emotion", "silence", "word", "question", "answer", "moment", "day", "time", "way", "sense", "uncertainty", "confusion", "understanding", "reaction", "response", "meaning", "loss", "absence", "grief", "anger", "sadness", "fear", "pain", "hope", "hurt", "doubt", "distance", "space", "mind", "heart", "breath", "name", "nothing", "anything", "something", "everything", "reason", "detail", "fact", "event", "yesterday", "tomorrow", "conversation", "hesitation", "feeling", "past", "present", "future", "anniversary", "death", "choice", "resolve", "weight", "edge", "fragment", "piece", "part", "effort", "possibility", "consciousness", "wakefulness", "intention", "relationship", "regret", "fact", "truth", "certainty", "self", "thoughtfulness", "clarity", "tension", "hesitation", "resolve", "expectation", "understanding", "difficulty", "contradiction", "emptiness", "stillness", "date", "sound", "shift", "air", "sorrow", "burden", "flicker", "loop", "circle", "echo", "depth", "rhythm", "body", "chest", "throat", "hand", "eye", "face", "voice", "heartbeat", "path", "situation", "challenge", "imprint", "point", "attempt", "need", "thought", "thoughtfulness", "settle", "tightness", "composure", "restraint", "pressure", "unease", "recognition", "recognize", "strain", "hesitate", "wait", "ache", "longing", "reserve"]
            let knownNouns = nouns(narration + " " + context)
            let unsupported = nouns(literalDescription(draft)).subtracting(knownNouns).subtracting(abstract).filter { !allowed.contains($0) }
            if !unsupported.isEmpty { issues.append("Unestablished concrete details: " + unsupported.sorted().prefix(8).joined(separator: ", ")) }
        }
        let known = people(narration + " " + context)
        for name in people(draft) where !known.contains(name) && !allowed.contains(name) { issues.append("New person: " + name) }
        for name in people(narration) where requireCoverage && !result.contains(name) { issues.append("Missing named person: " + name) }
        return issues
    }
}

public enum NarrationBeats {
    public static func format(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)
        let pieces = clean.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return pieces.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}
