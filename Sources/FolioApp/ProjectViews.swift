import SwiftUI
import FolioCore

struct ProjectLibraryView: View {
    @ObservedObject var store: Workspace
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack { Label("SYLLAVANE", systemImage: "book.closed").font(.system(size: 11, weight: .semibold)).tracking(3); Spacer(); Button("Settings") { store.showSettings = true }.buttonStyle(QuietButton()) }.foregroundStyle(Palette.secondary)
            if store.recoveredNarration != nil {
                HStack { Label("An interrupted transcript is available.", systemImage: "waveform"); Spacer(); Button("Recover") { store.recoverNarration() }; Button("Dismiss") { store.clearRecoveredNarration() } }.font(.system(size: 12))
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) { Text("Your writing projects.").font(.system(size: 36, design: .serif)); Text("Books, blogs, posts, and papers. A voice and context for each.").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                Spacer(); Button { store.showNewProject = true } label: { Label("New project", systemImage: "plus") }.buttonStyle(QuietButton(prominent: true))
            }
            HStack { Image(systemName: "magnifyingglass"); TextField("Find a project", text: $search).textFieldStyle(.plain); Spacer(); Button("Import project backup") { store.importProject() }.buttonStyle(QuietButton()) }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(store.projects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.updatedAt > $1.updatedAt }) { project in
                        Button { store.selectProject(project.id) } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack { Image(systemName: project.writingMode.icon).font(.system(size: 22, weight: .light)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 11)) }.foregroundStyle(Palette.secondary)
                                Text(project.name).font(.system(size: 23, design: .serif)).lineLimit(2)
                                Text(project.premise.isEmpty ? "A space for your next story." : project.premise).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2).frame(height: 36, alignment: .top)
                                HStack { Text("\(project.wordCount) words"); Text("·"); Text("\(project.characters.count) characters"); Spacer() }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                Text(project.writingMode.title + " · " + project.updatedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                        }.buttonStyle(.plain)
                    }
                }
                if store.projects.isEmpty { EmptyHint(icon: "books.vertical", title: "Start with a project.", detail: "Give your book a working title, then bring in your writing and introduce its characters.").frame(height: 280) }
            }
            Text("Saved privately on this Mac").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(48).background(Palette.background)
    }
}
struct ProjectOverviewView: View {
    @ObservedObject var store: Workspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Eyebrow(text: store.project?.writingMode.title ?? "Writing project")
                TextField("Project title", text: Binding(get: { store.project?.name ?? "" }, set: { value in store.edit { $0.name = value } })).font(.system(size: 34, design: .serif)).textFieldStyle(.plain)
                PanelField(title: "What are you writing about?", placeholder: store.project?.writingMode == .book ? "A premise, a question, a world you want to explore…" : "Your topic, purpose, and main points…", value: Binding(get: { store.project?.premise ?? "" }, set: { value in store.edit { $0.premise = value } }), lines: 2)
                PanelField(title: "Audience", placeholder: "Who is this for? What should they understand or feel?", value: Binding(get: { store.project?.audience ?? "" }, set: { value in store.edit { $0.audience = value } }), lines: 1)
                HStack(spacing: 12) {
                    Button("Continue writing") { store.tab = .manuscript }.buttonStyle(QuietButton(prominent: true))
                    Text("\(store.project?.wordCount ?? 0) words · \(store.project?.chapters.count ?? 0) " + (store.project?.writingMode == .book ? "chapters" : "draft groups")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                overviewCard("Your source material", icon: "doc.text", detail: "\(store.project?.sources.count ?? 0) sources · \(store.project?.sources.filter { $0.isStyleSample && $0.analysis != nil }.count ?? 0) analyzed style samples", button: "Open sources") { store.tab = .sources }
                Text(store.project?.writingMode == .book ? "Import your own writing to learn how you build scenes and reveal emotion. Choose continuation to carry your manuscript forward." : "Add your own writing to guide the voice, and reference material to support the points you want to make.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.secondary)
                if store.project?.writingMode == .book { overviewCard("The people in this book", icon: "person.2", detail: "\(store.project?.characters.count ?? 0) characters · \(store.project?.relationships.count ?? 0) connections", button: "Open characters") { store.characterSearch = ""; store.showCharacters = true }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], alignment: .leading) {
                    ForEach(store.project?.characters ?? []) { character in
                        Button { store.characterSearch = character.name; store.showCharacters = true } label: { HStack { Avatar(data: character.avatar, name: character.name); Text(character.name).font(.system(size: 12)); Spacer() }.padding(12).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                    }
                }
                }
                overviewCard("Voice & preferences", icon: "slider.horizontal.3", detail: "Source-backed guidance and your own direction", button: "Shape the voice") { store.showStyle = true }
            }.padding(36).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func overviewCard(_ title: String, icon: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) { Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.secondary); VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 17, design: .serif)); Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary) }; Spacer(); Button(button, action: action).buttonStyle(QuietButton()) }.padding(20).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
    }
}

struct PasteSourceView: View {
    @ObservedObject var store: Workspace
    let close: () -> Void
    @State private var name = ""
    @State private var text = ""
    @State private var isStyle = true
    var body: some View {
        SheetShell(title: "Bring a piece of your writing.", subtitle: store.project?.name ?? "", close: close) {
            PanelField(title: "Source name", placeholder: "A scene, a chapter, a working draft…", value: $name, lines: 1)
            TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden).padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8)).frame(height: 260).accessibilityLabel("Writing sample")
            Toggle("Learn my voice from this source", isOn: $isStyle).font(.system(size: 12))
            HStack { Text("\(text.split(whereSeparator: \.isWhitespace).count) words").font(.system(size: 11)).foregroundStyle(Palette.secondary); Spacer(); Button("Add to project") { store.addPastedSource(name: name, text: text, asStyleSample: isStyle); close() }.buttonStyle(QuietButton(prominent: true)).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 300_000) }
        }.frame(width: 620)
    }
}

struct SourceUseView: View {
    @ObservedObject var store: Workspace
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("How should Syllavane use this?").font(.system(size: 26, design: .serif))
            if let source = store.pendingSources.first {
                Text(source.name).font(.system(size: 13, weight: .medium))
                Text(String(source.text.prefix(350))).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                ForEach(SourceUse.allCases, id: \.self) { use in
                    Button { store.resolveSource(use) } label: {
                        VStack(alignment: .leading, spacing: 7) { Text(use.title).font(.system(size: 14, weight: .medium)); Text(use.explanation).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4) }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
                    }.buttonStyle(.plain)
                }
                HStack { Text("Original file stays unchanged.").font(.system(size: 10)).foregroundStyle(Palette.secondary); Spacer(); Button("Cancel import") { store.pendingSources.removeFirst() }.buttonStyle(QuietButton()) }
            }
        }.padding(28).frame(width: 550).background(Palette.background).foregroundStyle(Palette.text).preferredColorScheme(.dark).interactiveDismissDisabled()
    }
}
