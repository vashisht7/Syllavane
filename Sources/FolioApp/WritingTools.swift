import SwiftUI
import FolioCore

struct WritingSearch: View {
    @ObservedObject var store: Workspace
    @State private var query = ""
    @FocusState private var focused: Bool
    private var matches: [WritingMatch] { LibrarySearch.find(query, projects: store.projects) }
    var body: some View {
        SheetShell(title: "Find your words.", subtitle: "Search writing, narration, characters, and sources across your projects.", close: { store.showSearch = false }) {
            TextField("Search all writing", text: $query).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { if let first = matches.first { open(first) } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if matches.isEmpty { Text(query.isEmpty ? "Type a name, a phrase, or an idea you wrote." : "No matches. Try a shorter phrase.").foregroundStyle(Palette.secondary).padding(.vertical, 24) }
                    ForEach(matches) { result in
                        Button { open(result) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.kind.uppercased()).font(.system(size: 9)).foregroundStyle(Palette.secondary)
                                Text(result.title).font(.system(size: 13, weight: .medium))
                                Text(result.excerpt).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(3)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 360)
        }.frame(width: 620).onAppear { focused = true }
    }
    private func open(_ match: WritingMatch) {
        guard !store.dictation.recording && !store.dictation.transcribing else { store.toast = "Finish speaking before opening another passage."; return }
        store.selectProject(match.projectID)
        if let scene = match.sceneID { store.selectScene(scene) }
        if let name = match.characterName { store.characterSearch = name; store.tab = .characters }
        if match.kind == "Source" { store.tab = .sources }
        store.showSearch = false
    }
}
struct RevisionComparison: View {
    @ObservedObject var store: Workspace
    var body: some View {
        SheetShell(title: "Your words, before and after.", subtitle: "Review the revision before keeping it.", close: { store.showCompare = false }) {
            HStack(alignment: .top, spacing: 20) {
                passage("Before", text: store.revisionBefore ?? "")
                passage("After", text: store.revisionAfter ?? "")
            }
            HStack {
                Button("Undo change") { store.undoAIRevision() }.buttonStyle(QuietButton()).disabled(store.generating || store.proposal?.text != store.revisionAfter)
                Spacer()
                Button("Keep change") { store.keepAIRevision() }.buttonStyle(QuietButton(prominent: true))
            }
        }.frame(width: 800)
    }
    private func passage(_ title: String, text: String) -> some View {
        VStack(alignment: .leading) {
            Eyebrow(text: title)
            ScrollView { Text(text).font(.custom("Georgia", size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 380)
        }.frame(maxWidth: .infinity)
    }
}
