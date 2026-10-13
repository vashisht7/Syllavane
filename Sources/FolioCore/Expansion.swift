import Foundation

public enum ExpansionQuality {
    public static func isDeveloped(_ draft: String, from notes: String) -> Bool {
        func words(_ text: String) -> [String] { CharacterMatcher.normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let a = words(notes), b = words(draft)
        guard !a.isEmpty, a != b else { return false }
        // A ghostwritten scene must contribute more than punctuation, synonyms, or appended directions.
        guard b.count >= max(a.count + 20, Int(Double(a.count) * 1.5)) else { return false }
        let newWords = Set(b).subtracting(Set(a))
        guard newWords.count >= min(12, max(5, a.count / 3)) else { return false }
        if draft.range(of: #"(?i)(return only|expand this|write the scene|the final event|author notes|paragraph [123])"#, options: .regularExpression) != nil { return false }
        return true
    }
}

public struct ExpansionCandidates: Codable, Sendable {
    public var sentences: [String]
    public static func decode(_ text: String) throws -> [String] { try JSONDecoder().decode(Self.self, from: Data(text.utf8)).sentences }
}
public enum BeatExpansion {
    public static let candidateSystem = "Write alternatives for a psychological novel. Return JSON containing six separate candidate sentences of interior narration about the viewpoint character in the current event. Use third-person past tense unless the supplied voice explicitly requires another viewpoint or tense. Develop the feelings or hesitation already indicated. No locations, objects, physical actions, dialogue, invented memories, later events or anyone else's feelings. Do not declare an emotion absent or replace uncertainty with a definite feeling unless the author supplied that fact. Follow the supplied voice. /no_think"
    public static let anchorSystem = "Copy-edit this story beat into one clear fiction sentence. Correct grammar and keep the existing viewpoint. Preserve the event, relationships, uncertainty, negation and timing. No expansion or explanation. Return only the sentence. /no_think"
    public static func candidatePrompt(anchor: String, style: String, example: String, characters: String, prior: String, previous: String, instruction: String, retry: Bool) -> String {
        "VOICE:\n" + String(style.prefix(600)) + (example.isEmpty ? "" : "\nSTYLE EXAMPLE (technique only):\n" + String(example.prefix(350))) + (characters.isEmpty ? "" : "\nCHARACTER FACTS:\n" + String(characters.prefix(700))) + (prior.isEmpty ? "" : "\nBEFORE THIS EVENT:\n" + String(prior.suffix(400))) + (previous.isEmpty ? "" : "\nPRECEDING PROSE (do not repeat):\n" + String(previous.suffix(400))) + "\nAUTHOR DIRECTION: " + instruction + "\nCURRENT EVENT TO DEVELOP NOW:\n" + anchor + "\nFOCUS: " + focus(anchor) + "\nOffer six DIFFERENT sentences, each between 8 and 22 words, about this current event, adding new inner detail. Do not retell an earlier event or repeat earlier prose. " + (retry ? "Use simpler language about thoughts, feelings and unspoken words. Avoid concrete scenery." : "")
    }
    public static func viewpointDirection(notes: String, style: String) -> String {
        if style.lowercased().replacingOccurrences(of: "-", with: " ").contains("first person") || notes.range(of: #"^(I|We|My|Our)\b"#, options: .regularExpression) != nil { return "Use the author's first-person viewpoint." }
        let subject = viewpointSubject(notes: notes)
        let starts = ([subject] + viewpointPronouns(notes: notes)).joined(separator: ", ")
        return "MANDATORY VIEWPOINT: close third person, solely inside " + subject + "’s experience. Every sentence must begin with one of: " + starts + ". Never enter another person's thoughts. Never use I, my, me, we, our, or you. Describe only the supplied feeling, without resolving it. Keep each sentence short."
    }
    public static func viewpointSubject(notes: String) -> String {
        let excluded: Set<String> = ["The", "Then", "After", "Before", "Later", "That", "This", "Next", "Yesterday", "One", "When", "On", "In", "At", "She", "He", "They", "Her", "His", "Their", "Okay", "Well", "So", "Now", "Tomorrow", "Today", "A", "An", "As", "For"]
        if let first = notes.split(whereSeparator: \.isWhitespace).first.map(String.init), ["He", "She", "They"].contains(first) { return first }
        if let first = notes.split(whereSeparator: \.isWhitespace).first.map(String.init), first.first?.isUppercase == true, !excluded.contains(first) { return first.trimmingCharacters(in: .punctuationCharacters) }
        let tagger = NSLinguisticTagger(tagSchemes: [.nameType], options: 0); tagger.string = notes
        var subject = "the viewpoint character"
        tagger.enumerateTags(in: NSRange(notes.startIndex..., in: notes), scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range, _, stop in
            if tag == .personalName, let r = Range(range, in: notes) { subject = String(notes[r]); stop.pointee = true }
        }
        return subject
    }
    public static func viewpointPronouns(notes: String) -> [String] {
        if notes.range(of: #"\b(She|she|her|Her)\b"#, options: .regularExpression) != nil { return ["She", "Her"] }
        if notes.range(of: #"\b(He|he|his|His)\b"#, options: .regularExpression) != nil { return ["He", "His"] }
        return []
    }
    public static func focus(_ beat: String) -> String {
        let value = beat.lowercased()
        if value.contains("death") || value.contains("died") { return "Explore the grief or absence indicated by this event, leaving it unresolved. Do not invent memories, a cause of death, rituals, or later actions." }
        if value.contains("doesn't talk") || value.contains("didn't talk") || value.contains("did not speak") || value.contains("silence") { return "Explore the viewpoint character's difficulty in putting feelings into words. Keep the silence unbroken. Do not attribute new reactions to another person." }
        if value.contains("understand") || value.contains("uncertain") || value.contains("confused") { return "Explore uncertainty and the struggle to decide how to respond. Do not resolve the uncertainty or explain an unspecified earlier event." }
        return "Deepen the thoughts or feelings already indicated by the current event and character facts. If a feeling is unspecified, keep it understated rather than inventing a new motivation."
    }
    public static func beats(_ notes: String) -> [String] {
        let clean = notes.replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)
        let transitions = clean.replacingOccurrences(of: #"(?i)\s+(?:but\s+(?=(?:a |a certain |one |then |certain ))|until\s+(?=(?:his |her |their |the )))"#, with: "\nThen ", options: .regularExpression)
        let pieces = transitions.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Bound the number of calls for long narration, while retaining all the notes.
        let size = max(1, Int(ceil(Double(pieces.count) / 6)))
        return stride(from: 0, to: pieces.count, by: size).map { start in pieces[start..<min(start+size, pieces.count)].joined(separator: ". ") + "." }
    }
    public static func eventAnchor(edited: String, beat: String, context: String) -> String {
        // Normalize a dictated milestone, not its surrounding fiction: the relation and event
        // are copied from the narration. This fixes repeated “anniversary, death anniversary”.
        if beat.hasPrefix("Then "), beat.lowercased().contains("death anniversary"),
           let regex = try? NSRegularExpression(pattern: #"((?:his|her|their|our|my|[\p{L}]+['’]s)\s+[\p{L}]+)['’]s\s+(?:death\s+)?anniversary"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: beat, range: NSRange(beat.startIndex..., in: beat)) {
            let subject = (beat as NSString).substring(with: match.range(at: 1))
            return "Then the anniversary of " + subject + "’s death arrived."
        }
        let beatWords = beat.split(whereSeparator: \.isWhitespace).count
        let editWords = edited.split(whereSeparator: \.isWhitespace).count
        let singleBeat = editWords <= max(beatWords + 8, Int(Double(beatWords) * 1.6))
        var anchor = singleBeat && GroundingCheck.safeCopyEdit(edited, notes: beat, context: context) ? edited : beat
        for cue in ["The next day", "The following day", "Later that day", "That evening", "That morning"] {
            if anchor.lowercased().hasPrefix(cue.lowercased()), !beat.lowercased().contains(cue.lowercased()) {
                anchor = String(anchor.dropFirst(cue.count)).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            }
            if beat.lowercased().hasPrefix(cue.lowercased()), !anchor.lowercased().contains(cue.lowercased()) { anchor = cue + ", " + anchor }
        }
        return anchor
    }
    public static func select(_ candidates: [String], beat: String, context: String, preceding: String, limit: Int = 2, viewpointNotes: String? = nil, allowFirstPerson: Bool = false) -> [String] {
        var selected: [String] = []
        let allowed = CharacterMatcher.normalized(beat + " " + context)
        for raw in candidates {
            let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let notes = viewpointNotes, !allowFirstPerson, notes.range(of: #"^(I|We|My|Our)\b"#, options: .regularExpression) == nil {
                let starts = [viewpointSubject(notes: notes)] + viewpointPronouns(notes: notes)
                if !starts.contains(where: { candidate.hasPrefix($0 + " ") || candidate.hasPrefix($0 + "’s ") || candidate.hasPrefix($0 + "'s ") }) { continue }
            }
            let tokens = candidate.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 9, tokens.count <= 65,
                  !candidate.contains("\n"), candidate.last.map({ ".!?".contains($0) }) == true,
                  GroundingCheck.issues(draft: candidate, narration: beat, context: context, requireCoverage: false).isEmpty,
                  AuthorMemory.conflicts(draft: candidate, notes: beat + " " + context).isEmpty else { continue }
            let value = CharacterMatcher.normalized(candidate)
            // Metaphorical interior detail is allowed; unsolicited physical events are not.
            let literal = GroundingCheck.literalDescription(value)
            // Absence of a supplied emotion is not permission to declare it absent.
            if let denial = literal.range(of: #"\b(?:no|without|never felt|did not feel|didn't feel)\s+(?:grief|sadness|fear|anger|love|regret|remorse)\b"#, options: .regularExpression),
               !allowed.contains(String(literal[denial])) { continue }
            let newActions = ["sat", "stood", "walked", "drove", "gripped", "opened", "closed", "smiled", "laughed", "cried", "hugged", "kissed", "died", "killed", "arrived", "left", "met", "saw", "heard", "spoke", "said", "told", "talked", "shouted", "screamed", "forgave", "woke", "awoke", "slept", "remember", "remembers", "remembered"]
            if newActions.contains(where: { action in literal.range(of: "(?<![\\p{L}])" + action + "(?![\\p{L}])", options: .regularExpression) != nil && allowed.range(of: "(?<![\\p{L}])" + action + "(?![\\p{L}])", options: .regularExpression) == nil }) { continue }
            if ["first time", "weeks", "months", "years", "funeral", "accident", "reconciliation", "photograph", "birthday", "his father's death", "his father’s death"].contains(where: { value.contains($0) && !allowed.contains($0) }) { continue }
            if candidate.range(of: #"(?i)\b(I|my|me|we|our|you|your)\b"#, options: .regularExpression) != nil && beat.range(of: #"(?i)\b(I|my|me|we|our|you|your)\b"#, options: .regularExpression) == nil && !allowFirstPerson { continue }
            // The viewpoint character's silence cannot become another person's behavior.
            if let regex = try? NSRegularExpression(pattern: #"(?:his|her|their)\s+(?:father|mother|brother|sister|partner|friend)['’]s\s+(?:silence|anger|fear|hesitation|grief|sadness)"#),
               regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil,
               !allowed.contains(value) { continue }
            if ["anything else", "everything he had ever", "never before", "always been", "quiet certainty", "truth he had long known", "knew exactly", "finally understood", "the last one", "the previous anniversary", "every anniversary", "always did", "used to", "every time", "long before"].contains(where: { value.contains($0) && !allowed.contains($0) }) { continue }
            if value.contains("paragraph") || value.contains("candidate") || value.contains("the author") { continue }
            let existing = preceding + "\n" + selected.joined(separator: " ")
            let previousSentences = preceding.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            if previousSentences.contains(where: { Retrieval.lexicalScore(query: candidate, passage: $0) > 0.65 }) { continue }
            if existing.contains(candidate) || selected.contains(where: { Retrieval.lexicalScore(query: $0, passage: candidate) > 0.65 }) { continue }
            if Retrieval.lexicalScore(query: candidate, passage: beat) > 0.8 { continue }
            selected.append(candidate)
            if selected.count == limit { break }
        }
        return selected
    }
    public static func paragraph(anchor: String, elaboration: [String]) -> String {
        anchor.trimmingCharacters(in: .whitespacesAndNewlines) + (elaboration.isEmpty ? "" : " " + elaboration.joined(separator: " "))
    }
}
