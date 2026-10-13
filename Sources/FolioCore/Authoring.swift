import Foundation

public struct CharacterTrait: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var category: String
    public var value: String
    public init(category: String, value: String = "") { self.category = category; self.value = value }
    public static let suggestions = ["Desire", "Fear", "Contradiction", "Belief", "Boundary", "Wound", "History", "Secret", "Voice", "Mannerism", "Appearance", "Strength", "Flaw", "Attachment", "Under pressure", "Public self", "Private self"]
    public static func question(for category: String) -> String {
        switch category {
        case "Desire": return "What do they want, and what do they actually need?"
        case "Fear": return "What are they afraid to lose or admit?"
        case "Contradiction": return "Where do their actions contradict their beliefs?"
        case "Belief": return "What conviction shapes their choices?"
        case "Boundary": return "What line would they never cross? What could change that?"
        case "Wound": return "What past hurt still shapes their reactions?"
        case "Voice": return "How do they speak, hesitate, or avoid saying things?"
        case "Under pressure": return "Do they withdraw, confront, appease, or take control?"
        case "Attachment": return "How do they seek closeness or protect themselves from it?"
        case "Public self": return "What version of themselves do they show others?"
        case "Private self": return "Who are they when nobody is watching?"
        default: return "Describe this characteristic in your own words…"
        }
    }
}
public struct StyleObservation: Codable, Identifiable, Equatable, Sendable {
    public var dimension: String
    public var observation: String
    public var evidence: String
    public var guidance: String
    public var id: String { dimension }
    public init(dimension: String, observation: String, evidence: String, guidance: String) {
        self.dimension = dimension; self.observation = observation; self.evidence = evidence; self.guidance = guidance
    }
}
public struct StyleAnalysis: Codable, Equatable, Sendable {
    public var observations: [StyleObservation]
    public static let dimensions = ["Scene construction", "Inner experience", "Emotional restraint", "Sentence rhythm", "Dialogue & subtext", "Imagery & detail"]
    public static func decode(_ text: String, source: String) throws -> StyleAnalysis {
        let result = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        var seen = Set<String>()
        let valid = result.observations.filter {
            dimensions.contains($0.dimension) && !$0.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && source.contains($0.evidence) && !$0.observation.isEmpty && !$0.guidance.isEmpty && seen.insert($0.dimension).inserted
        }
        guard !valid.isEmpty else { throw FolioError.message("The analysis did not include verifiable examples. Try a longer scene or analyze again.") }
        return StyleAnalysis(observations: valid)
    }
    public var guide: String { observations.map { "\($0.dimension): \($0.guidance)" }.joined(separator: "\n") }
}
public struct WritingMeasurements: Equatable, Sendable {
    public let words: Int
    public let paragraphs: Int
    public let averageSentenceWords: Int
    public init(_ text: String) {
        words = text.split(whereSeparator: \.isWhitespace).count
        paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let sentences = text.split { ".!?".contains($0) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        averageSentenceWords = sentences.isEmpty ? 0 : Int((Double(words) / Double(sentences.count)).rounded())
    }
}
public enum TranscriptFilter {
    /// Deliberately narrow: never remove narrated actions such as “she sighs”.
    public static func clean(_ text: String, removeFillers: Bool = true) -> String {
        var value = text.replacingOccurrences(of: #"(?i)[\[\(](?:music|silence|noise|background noise|breathing|breath|coughing|cough|laughter|laughing|sigh|sighing|inaudible|blank_audio)[\]\)]"#, with: "", options: .regularExpression)
        if removeFillers { value = value.replacingOccurrences(of: #"(?i)(?<![\p{L}\p{N}])(?:uh+|um+|erm+)(?![\p{L}\p{N}])[,\s]*"#, with: "", options: .regularExpression) }
        return value.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func hasVoiceEnergy(_ pcm: Data) -> Bool {
        guard pcm.count >= 6400 else { return false }
        var voiced = 0
        for offset in stride(from: 0, to: pcm.count - 1, by: 640) {
            let end = min(offset + 640, pcm.count - pcm.count % 2)
            var sum = 0.0
            for i in stride(from: offset, to: end, by: 2) {
                let sample = Double(Int16(bitPattern: UInt16(pcm[i]) | UInt16(pcm[i+1]) << 8)) / 32768
                sum += sample * sample
            }
            if sqrt(sum / Double(max(1, (end-offset)/2))) > 0.008 { voiced += 1 }
        }
        return voiced >= 10
    }
}
public enum DraftAdjustments {
    public static let all: [(String, String)] = [
        ("Less description", "Reduce descriptive detail while preserving events and emotional meaning."),
        ("Tone down", "Make emotion more restrained; remove melodrama without flattening the character."),
        ("Explain more", "Clarify and develop the supplied meaning with more detail in the author’s voice. Do not invent facts, history or events."),
        ("More informative", "Make the supplied information clearer and more useful while preserving the author’s voice. Use only established facts; do not invent evidence."),
        ("More inner depth", "Explore the established character's conflicting thoughts without inventing history or events."),
        ("More subtext", "Express the existing tension through pauses and gestures instead of explaining it."),
        ("Tighter pacing", "Remove repetition and tighten transitions without skipping the narrated events."),
        ("Stay in the moment", "Slow this moment through meaningful actions and perception, without adding plot."),
        ("Natural dialogue", "Make existing dialogue sound natural to these characters. Preserve its meaning."),
        ("Closer to my voice", "Follow the project writing samples' narrative distance, scene construction, and sentence rhythm more closely.")
    ]
}

public enum DraftQuality {
    public static func echoesNarration(_ draft: String, narration: String) -> Bool {
        func words(_ text: String) -> [String] { text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let a = words(draft), b = words(narration)
        guard b.count >= 8, !a.isEmpty else { return false }
        if a == b { return true }
        let draftText = a.joined(separator: " ")
        let copied = stride(from: 0, to: max(1, b.count - 7), by: 8).filter { start in
            draftText.contains(b[start..<min(start + 8, b.count)].joined(separator: " "))
        }.count
        return Double(copied) / Double(max(1, b.count / 8)) > 0.85 && a.count < b.count * 2
    }
}
