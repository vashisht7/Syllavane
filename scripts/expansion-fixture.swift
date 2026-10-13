import Foundation

@main struct Fixture {
    static func main() throws {
        let input = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
        let command = input["command"] as? String ?? "beats"
        let notes = input["notes"] as? String ?? ""
        let context = input["context"] as? String ?? ""
        var result: Any = []
        switch command {
        case "beats": result = BeatExpansion.beats(notes)
        case "prompt":
            result = ["system": BeatExpansion.candidateSystem, "user": BeatExpansion.candidatePrompt(anchor: input["anchor"] as? String ?? notes, style: input["style"] as? String ?? "", example: input["example"] as? String ?? "", characters: context, prior: input["prior"] as? String ?? "", previous: input["previous"] as? String ?? "", instruction: "Render the author's narrated feelings, actions and imagined details in their own writing style.", retry: input["retry"] as? Bool ?? false), "anchorSystem": BeatExpansion.anchorSystem]
        case "select": result = BeatExpansion.select(input["candidates"] as? [String] ?? [], beat: input["beat"] as? String ?? notes, context: context, preceding: input["previous"] as? String ?? "")
        case "anchor": result = ["text": BeatExpansion.eventAnchor(edited: input["text"] as? String ?? "", beat: input["beat"] as? String ?? notes, context: context)]
        case "check":
            let text = input["text"] as? String ?? ""
            result = ["expanded": ExpansionQuality.isDeveloped(text, from: notes), "issues": GroundingCheck.issues(draft: text, narration: notes, context: context)]
        default: break
        }
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]), encoding: .utf8)!)
    }
}
