import Foundation

public enum PromptBuilder {
    public static func system(project: StoryProject) -> String {
        """
        Develop the author’s notes into faithful finished writing. /no_think
        \(project.writingMode.guidance)
        The AUTHOR NOTES are authoritative unless the author explicitly corrected a fact in their own edits. Author corrections override older narration; generated drafts never count as new evidence. Preserve their timeline, uncertainty and relationships. Never explain an unspecified earlier event, invent a reconciliation, change who is alive, or introduce new people, locations or major props. Prior writing provides continuity; style examples provide technique only. For fiction, develop each supplied beat in two or three sentences of restrained prose. Show only the feelings already indicated; uncertainty must remain unresolved. Never turn confusion into memory loss, doubt that an event occurred, or emotional numbness. Use no imagined memories, furniture, weather, gestures, or dialogue unless supplied. For nonfiction, preserve the author's claims and intention without adding motives, evidence or named methods. If a concrete detail is unspecified, leave it unspecified. Avoid prefacing or explaining the draft. Return finished writing only.
        VOICE: \(project.style.prefix(700))
        SOURCE TECHNIQUES: \(project.sources.filter(\.isStyleSample).compactMap { $0.analysis?.guide }.joined(separator: "\n").prefix(1000))
        PREFERENCES: \(project.preferences.joined(separator: "; ").prefix(500))
        AUDIENCE: \((project.audience ?? "").prefix(300))
        """
    }
    public static func scene(project: StoryProject, scene: Scene, instruction: String, selection: String, passages: [Passage]) -> String {
        let style = passages.filter(\.isStyle).prefix(1).map { String($0.text.prefix(900)) }.joined()
        let facts = passages.filter { !$0.isStyle }.prefix(2).map { "\($0.label): \($0.text)" }.joined(separator: "\n")
        return """
        PREMISE: \(project.premise.prefix(500))
        STORY FACTS (never import people or plot from the style sample):
        \(StoryContext.facts(project: project, scene: scene))
        \(StoryContext.continuity(project, before: scene.id))
        RELEVANT REFERENCES:
        \(facts.prefix(1500))
        STYLE EXAMPLE (rhythm and narrative distance only):
        \(style)
        \(selection.isEmpty ? "" : "REWRITE ONLY THIS PASSAGE:\n" + String(selection.prefix(1800)))
        EXISTING PASSAGE: \(scene.text.suffix(900))
        AUTHOR NOTES, IN ORDER (every beat must appear):
        \(NarrationBeats.format(scene.brief).prefix(6500))
        LEARNED AUTHOR CHOICES:
        \(AuthorMemory.prompt(project: project, sceneID: scene.id, query: scene.brief))
        AUTHOR'S REQUEST: \(instruction)
        \(project.writingMode == .book ? "Write a developed scene of about " + String(max(70, min(350, scene.brief.split(whereSeparator: \.isWhitespace).count * 3))) + " words, unless the author's voice or request calls for another length. Use two or three sentences for each beat, revealing the stated inner experience. Do not just paraphrase the notes." : "")
        Preserve every event above, in order. Develop only those events. End at the narrated stopping point. \(selection.isEmpty ? "Return only the new writing." : "Return only the replacement passage.")
        """
    }
    public static func cleanTranscript(_ text: String) -> String {
        var result = text
        if let range = result.range(of: "</think>") { result = String(result[range.upperBound...]) }
        if result.hasPrefix("<think>") { return "" }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
