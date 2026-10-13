import Foundation

@main struct Fixture {
    static func main() throws {
        var project = StoryProject(name: "Joseph regression")
        project.style = "Close third person, restrained emotion. Reveal uncertainty without resolving it."
        project.characters = [StoryCharacter(name: "Joseph"), StoryCharacter(name: "George", details: "Joseph's father.")]
        let notes = "The next day Joseph couldn't understand what happened yesterday and how he should react for it. So he doesn't talk to his father George for many days but a certain day comes: his mother's death anniversary."
        project.chapters[0].scenes[0].brief = notes
        if CommandLine.arguments.count > 1 {
            let draft = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if CommandLine.arguments[1] == "check-safe" {
                print(GroundingCheck.safeCopyEdit(draft, notes: notes, context: StoryContext.facts(project: project, scene: project.scenes[0])) ? "true" : "false"); return
            }
            let issues = GroundingCheck.issues(draft: draft, narration: notes, context: StoryContext.facts(project: project, scene: project.scenes[0]))
            print(String(data: try JSONEncoder().encode(issues), encoding: .utf8)!)
        } else {
            let prompt = PromptBuilder.scene(project: project, scene: project.scenes[0], instruction: "Develop the narrated feelings and timeline faithfully.", selection: "", passages: [])
            let output = ["system": PromptBuilder.system(project: project), "user": prompt, "notes": notes, "context": StoryContext.facts(project: project, scene: project.scenes[0])]
            print(String(data: try JSONEncoder().encode(output), encoding: .utf8)!)
        }
    }
}
