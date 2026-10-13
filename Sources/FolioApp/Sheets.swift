import SwiftUI
import FolioCore

struct SheetShell<Content: View>: View {
    let title: String
    let subtitle: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 25, design: .serif)); Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(); IconButton(icon: "xmark", help: "Close", action: close) }
            content()
        }.padding(28).background(Palette.background).foregroundStyle(Palette.text).preferredColorScheme(.dark)
    }
}

struct NewProjectView: View {
    @ObservedObject var store: Workspace
    @State private var name = ""
    @State private var mode: WritingMode = .book
    @FocusState private var focused: Bool
    var body: some View {
        SheetShell(title: "What are you writing?", subtitle: "Choose a format. Give it a name now or later.", close: { store.showNewProject = false }) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(WritingMode.allCases, id: \.self) { option in
                    Button { mode = option } label: { HStack { Image(systemName: option.icon); Text(option.title); Spacer(); if mode == option { Image(systemName: "checkmark") } }.padding(14).background(mode == option ? Palette.hover : Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                }
            }
            PanelField(title: "Project name", placeholder: "Working title (optional)", value: $name, lines: 1).focused($focused)
            HStack { Spacer(); Button("Cancel") { store.showNewProject = false }.buttonStyle(QuietButton()); Button("Start writing") { store.newProject(name: name, mode: mode); store.showNewProject = false }.buttonStyle(QuietButton(prominent: true)).keyboardShortcut(.defaultAction) }
        }.frame(width: 480).onAppear { focused = true }
    }
}

struct CharactersView: View {
    @ObservedObject var store: Workspace
    @State private var editing: StoryCharacter?
    @State private var search = ""
    @State private var aliases = ""
    @State private var development = ""
    @State private var effectiveScene: UUID?
    @State private var detailMode = 0
    @State private var editingProjectID: UUID?
    private var matches: [StoryCharacter] { CharacterMatcher.suggestions(for: search, in: store.project?.characters ?? []) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { VStack(alignment: .leading, spacing: 8) { Eyebrow(text: store.project?.name ?? "Project"); Text("Characters").font(.system(size: 29, design: .serif)); Text("A shared cast for this project. Changes are saved when you leave a character.").font(.system(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(); Button("New character") { select(StoryCharacter(name: search)) }.buttonStyle(QuietButton(prominent: true)) }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Find a character…", text: $search).textFieldStyle(.plain).padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 7)).font(.system(size: 12))
                    ScrollView { VStack(spacing: 6) {
                        ForEach(matches) { character in
                            Button { select(character) } label: { HStack(spacing: 9) { Avatar(data: character.avatar, name: character.name, size: 28); Text(character.name).font(.system(size: 12)); Spacer() }.padding(9).background(editing?.id == character.id ? Palette.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain)
                        }
                        if matches.isEmpty && !search.isEmpty { Text("No match. Add a new character, or search another spelling.").font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(8) }
                    } }
                }.frame(width: 190)
                Rectangle().fill(Palette.line).frame(width: 1)
                if editing != nil { characterForm }
                else { EmptyHint(icon: "person.crop.square", title: "Meet your characters.", detail: "Choose someone on the left, or add a new character.") }
            }.frame(maxHeight: .infinity)
        }.padding(30).onAppear {
            editingProjectID = store.projectID; search = store.characterSearch
            if let match = matches.first, !search.isEmpty { select(match) }
            else if let first = matches.first { select(first) }
            else { select(StoryCharacter(name: search)) }
        }.onDisappear { saveCurrent() }
    }
    private var characterForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Button { if let data = store.chooseAvatar() { editing?.avatar = data } } label: { Avatar(data: editing?.avatar, name: editing?.name ?? "", size: 52) }.buttonStyle(.plain).help("Choose character avatar")
                VStack(alignment: .leading, spacing: 8) { TextField("Character name", text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 })).font(.system(size: 21, design: .serif)).textFieldStyle(.plain); Button("Upload face…") { if let data = store.chooseAvatar() { editing?.avatar = data } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }
            PanelField(title: "Aliases & corrected spellings", placeholder: "Separate names with commas", value: $aliases, lines: 1)
            Picker("Edit mode", selection: $detailMode) { Text("Character profile").tag(0); Text("Development").tag(1) }.pickerStyle(.segmented)
            if detailMode == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let project = store.project, let character = editing, let sid = store.sceneID {
                            let evidence = AuthorMemory.characterEvidence(project: project, character: character, at: sid)
                            if !evidence.isEmpty {
                                DisclosureGroup("From your narration and edits") { ForEach(evidence, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(Palette.secondary).textSelection(.enabled).padding(.vertical, 5) } }.font(.system(size: 12))
                            }
                        }
                        Text("Build a person, one characteristic at a time.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        HStack {
                            Menu { ForEach(CharacterTrait.suggestions, id: \.self) { category in Button(category) { addTrait(category) }.disabled((editing?.traits ?? []).contains { $0.category == category }) } } label: { Label("Add characteristic", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                            Spacer(); Text("Optional · choose what matters").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        if editing?.traits?.isEmpty != false {
                            HStack { ForEach(["Desire", "Fear", "Under pressure"], id: \.self) { category in Button(category) { addTrait(category) }.buttonStyle(QuietButton()) } }
                        }
                        ForEach(editing?.traits ?? []) { trait in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Characteristic", text: traitBinding(trait.id, category: true)).font(.system(size: 12, weight: .medium)).textFieldStyle(.plain)
                                    Button { editing?.traits?.removeAll { $0.id == trait.id } } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("Remove characteristic")
                                }
                                TextField(CharacterTrait.question(for: trait.category), text: traitBinding(trait.id), axis: .vertical).lineLimit(2...5).font(.system(size: 12)).textFieldStyle(.plain).accessibilityLabel(trait.category)
                            }.padding(12).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button("Add a custom characteristic") { addTrait("Custom characteristic") }.buttonStyle(QuietButton())
                        DisclosureGroup("Additional notes") { PanelField(title: "Notes", placeholder: "Anything that doesn't fit a characteristic…", value: Binding(get: { editing?.details ?? "" }, set: { editing?.details = $0 }), lines: 3).padding(.top, 8) }.font(.system(size: 11))
                    }
                }
            } else {
                Picker("Effective from", selection: $effectiveScene) { ForEach(store.project?.scenes ?? []) { scene in Text(scene.title).tag(Optional(scene.id)) } }.font(.system(size: 12))
                PanelField(title: "What changes?", placeholder: "Describe the shift in their behavior or beliefs…", value: $development, lines: 3)
                ScrollView { VStack(alignment: .leading, spacing: 10) {
                    ForEach(editing?.developments ?? []) { item in
                        HStack(alignment: .top) { VStack(alignment: .leading, spacing: 4) { Text(store.project?.scenes.first { $0.id == item.sceneID }?.title ?? "Scene").font(.system(size: 10)).foregroundStyle(Palette.secondary); TextField("Development", text: Binding(get: { item.note }, set: { value in if let index = editing?.developments.firstIndex(where: { $0.id == item.id }) { editing?.developments[index].note = value } }), axis: .vertical).textFieldStyle(.plain).font(.system(size: 11)).lineSpacing(3) }; Spacer(); Button { editing?.developments.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle").foregroundStyle(Palette.muted) }.buttonStyle(.plain).help("Remove development") }.padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                } }
            }
            Spacer(minLength: 0)
            HStack {
                if let character = editing, store.project?.characters.contains(where: { $0.id == character.id }) == true {
                    Button("Include in scene") { store.editScene { if !$0.characterIDs.contains(character.id) { $0.characterIDs.append(character.id) } }; store.flush(); store.toast = "Added to scene" }.buttonStyle(QuietButton())
                }
                Spacer()
                Button("Save character") { saveCurrent()                }.buttonStyle(QuietButton(prominent: true)).disabled(editing?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func addTrait(_ category: String) {
        if editing?.traits == nil { editing?.traits = [] }
        editing?.traits?.append(CharacterTrait(category: category))
    }
    private func traitBinding(_ id: UUID, category: Bool = false) -> Binding<String> {
        Binding(get: { let trait = editing?.traits?.first { $0.id == id }; return (category ? trait?.category : trait?.value) ?? "" }, set: { value in
            guard let index = editing?.traits?.firstIndex(where: { $0.id == id }) else { return }
            if category { editing?.traits?[index].category = value } else { editing?.traits?[index].value = value }
        })
    }
    private func saveCurrent() {
        guard let editingProjectID, var character = editing, !character.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        character.name = character.name.trimmingCharacters(in: .whitespacesAndNewlines)
        character.aliases = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !development.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let effectiveScene { character.developments.append(Development(sceneID: effectiveScene, note: development)); development = "" }
        if store.projects.first(where: { $0.id == editingProjectID })?.characters.first(where: { $0.id == character.id }) != character { store.saveCharacter(character, in: editingProjectID) }
        editing = store.projects.first(where: { $0.id == editingProjectID })?.characters.first { $0.id == character.id }; aliases = editing?.aliases.joined(separator: ", ") ?? ""
    }
    private func select(_ character: StoryCharacter) { saveCurrent(); editing = character; aliases = character.aliases.joined(separator: ", "); development = ""; effectiveScene = store.sceneID; detailMode = 0 }
}

struct StyleView: View {
    @ObservedObject var store: Workspace
    @State private var style = ""
    @State private var premise = ""
    var body: some View {
        SheetShell(title: "What I’ve learned.", subtitle: "Your project memory. Review, correct, or forget what guides the writing.", close: { store.showStyle = false }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PanelField(title: "Story premise", placeholder: "The world, central conflict, and what this story is about…", value: $premise, lines: 3)
                    PanelField(title: "Writing style", placeholder: "For example: close third person, restrained dialogue, slow psychological detail, short sensory descriptions…", value: $style, lines: 6)
                    if let sources = store.project?.sources.filter({ $0.isStyleSample && $0.analysis != nil }), !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Learned from this book's sources")
                            ForEach(sources) { source in
                                DisclosureGroup(source.name) { Text(source.analysis?.guide ?? "").font(.system(size: 12)).lineSpacing(5).padding(.top, 8) }.font(.system(size: 12))
                            }
                            Text("These guides and original excerpts are used automatically. Add your own direction above to refine them.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }
                    if let suggestion = store.styleSuggestion {
                        VStack(alignment: .leading, spacing: 12) { Eyebrow(text: "Suggested from your samples"); Text(suggestion).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled); Button("Use this style guide") { style = suggestion; store.styleSuggestion = nil }.buttonStyle(QuietButton()) }.padding(16).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    if let edits = store.project?.authorEdits, !edits.isEmpty {
                        DisclosureGroup("Learning from your edits · \(edits.count) examples") {
                            ForEach(edits.suffix(12).reversed()) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Your version").font(.system(size: 10, weight: .medium))
                                    Text(AuthorMemory.contrast(before: item.before, after: item.after).1).font(.system(size: 11)).lineLimit(5)
                                    Button("Forget this example") { store.edit { $0.authorEdits?.removeAll { $0.id == item.id } }; store.flush(reason: "Learning example removed") }.buttonStyle(.plain).font(.system(size: 10))
                                }.padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }.font(.system(size: 12))
                    }
                    if let examples = store.project?.approvedRewrites, !examples.isEmpty {
                        DisclosureGroup("Rewrites you kept · \(examples.count) examples") {
                            Text("These examples guide style. Character and story facts come from your narration and your own edits.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            ForEach(examples.reversed()) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.instruction).font(.system(size: 11, weight: .medium))
                                    Text(AuthorMemory.contrast(before: item.before, after: item.after).1).font(.system(size: 11)).lineLimit(5)
                                    Button("Forget this example") { store.edit { $0.approvedRewrites?.removeAll { $0.id == item.id } }; store.flush(reason: "Approved rewrite forgotten") }.buttonStyle(.plain).font(.system(size: 10))
                                }.padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }.font(.system(size: 12))
                    }
                    if let directions = store.project?.authorDirections, !directions.isEmpty {
                        DisclosureGroup("Directions you’ve given · \(directions.count)") {
                            ForEach(directions.reversed()) { direction in
                                HStack { Text(direction.text).font(.system(size: 12)); Spacer(); Button("Forget") { store.edit { $0.authorDirections?.removeAll { $0.id == direction.id } }; store.flush() }.buttonStyle(QuietButton()) }.padding(.vertical, 5)
                            }
                        }
                    }
                    if let preferences = store.project?.preferences, !preferences.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Remembered feedback")
                            ForEach(preferences, id: \.self) { preference in HStack { Text(preference).font(.system(size: 12)); Spacer(); Button { store.edit { $0.preferences.removeAll { $0 == preference } }; store.flush(reason: "Preference removed") } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Palette.secondary) }.buttonStyle(.plain).help("Forget preference") }.padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 6)) }
                        }
                    }
                }
            }.frame(maxHeight: 450)
            HStack { Button("Review source analysis") { store.showStyle = false; store.tab = .sources }.buttonStyle(QuietButton()).disabled(store.generating || store.project?.sources.isEmpty != false); Spacer(); Button("Save voice") { store.edit { $0.style = style; $0.premise = premise }; store.flush(reason: "Style updated"); store.showStyle = false }.buttonStyle(QuietButton(prominent: true)) }
        }.frame(width: 630).onAppear { style = store.project?.style ?? ""; premise = store.project?.premise ?? "" }
    }
}

struct RelationshipView: View {
    @ObservedObject var store: Workspace
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var label = ""
    var body: some View {
        SheetShell(title: "Connect the characters.", subtitle: "A relationship becomes part of your story's context.", close: { store.showRelationship = false }) {
            HStack {
                Picker("From", selection: $from) { ForEach(store.project?.characters ?? []) { Text($0.name).tag(Optional($0.id)) } }
                Image(systemName: "arrow.right").foregroundStyle(Palette.secondary)
                Picker("To", selection: $to) { ForEach(store.project?.characters ?? []) { Text($0.name).tag(Optional($0.id)) } }
            }
            PanelField(title: "Relationship", placeholder: "Estranged siblings; mutual respect, unspoken resentment…", value: $label, lines: 3)
            HStack { Spacer(); Button("Add connection") { if let from, let to { store.addRelationship(from: from, to: to, label: label); store.showRelationship = false } }.buttonStyle(QuietButton(prominent: true)).disabled(from == nil || to == nil || from == to || label.isEmpty) }
        }.frame(width: 560).onAppear { from = store.project?.characters.first?.id; to = store.project?.characters.dropFirst().first?.id }
    }
}

struct HistoryView: View {
    @ObservedObject var store: Workspace
    @State private var selected: Int64?
    @State private var confirm = false
    var body: some View {
        SheetShell(title: "Every version, kept.", subtitle: "Restore a project checkpoint. Your current work is saved before restoring.", close: { store.showHistory = false }) {
            HStack(alignment: .top, spacing: 20) {
                ScrollView { VStack(spacing: 6) { ForEach(store.history) { revision in
                    Button { selected = revision.id } label: { VStack(alignment: .leading, spacing: 6) { Text(revision.reason).font(.system(size: 12, weight: .medium)); Text(revision.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 10)).foregroundStyle(Palette.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(selected == revision.id ? Palette.hover : Palette.tile).clipShape(RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain)
                } } }.frame(width: 210)
                if let revision = store.history.first(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 14) { Text("\(revision.project.wordCount) words · \(revision.project.characters.count) characters").font(.system(size: 11)).foregroundStyle(Palette.secondary); ScrollView { Text(revision.project.markdown()).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }; Button("Restore this version") { confirm = true }.buttonStyle(QuietButton(prominent: true)) }
                } else { EmptyHint(icon: "clock", title: "Your writing, over time.", detail: "Select a checkpoint to preview it.") }
            }.frame(height: 420)
        }.frame(width: 760)
        .confirmationDialog("Restore this project version?", isPresented: $confirm) { Button("Restore version") { if let revision = store.history.first(where: { $0.id == selected }) { store.restore(revision) } } } message: { Text("This restores characters, sources, and chapters together. The current version remains in history.") }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Workspace
    @ObservedObject var models: LocalEngines
    var body: some View {
        SheetShell(title: "Quietly powerful. Entirely local.", subtitle: "Your words and recordings stay on this Mac.", close: { store.showSettings = false }) {
            ScrollView { VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Button { if let data = store.chooseAvatar() { store.edit { $0.assistantAvatar = data }; store.flush() } } label: { Avatar(data: store.project?.assistantAvatar, name: "S", size: 46) }.buttonStyle(.plain).help("Choose your assistant's avatar")
                    VStack(alignment: .leading, spacing: 5) { Text("Your writing companion").font(.system(size: 13, weight: .medium)); Text("Click to choose an avatar for this project.").font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                    Spacer()
                }.padding(.bottom, 12)
                Eyebrow(text: "Dictation")
                Toggle("Remove filler sounds (um, uh)", isOn: Binding(get: { store.dictation.removeFillers }, set: { store.dictation.removeFillers = $0; store.objectWillChange.send() })).font(.system(size: 12))
                Text("Non-speech labels are filtered. Story actions such as ‘she sighed’ stay intact. For cleaner audio, use a close microphone; background voices can still be transcribed.").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
                Eyebrow(text: "Local models")
                ForEach(models.specs) { spec in
                    HStack(spacing: 12) { Image(systemName: spec.id == "writer" ? "text.cursor" : spec.id == "speech" ? "waveform" : "point.3.connected.trianglepath.dotted").font(.system(size: 17)).foregroundStyle(Palette.secondary).frame(width: 24); VStack(alignment: .leading, spacing: 5) { Text(spec.name).font(.system(size: 12, weight: .medium)); Text("\(ByteCountFormatter.string(fromByteCount: spec.bytes, countStyle: .file)) · \(spec.license)").font(.system(size: 10)).foregroundStyle(Palette.secondary) }; Spacer(); Image(systemName: models.modelStatus[spec.id] == true ? "checkmark.circle" : "arrow.down.circle").foregroundStyle(Palette.secondary) }.padding(14).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if models.preparing { ProgressView(value: models.downloadProgress).tint(Color(white: 0.7)) }
                HStack { if models.ready { Image(systemName: "checkmark.shield") }; Text(models.status).font(.system(size: 11)); Spacer() }.foregroundStyle(Palette.secondary)
                if let error = models.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.text).textSelection(.enabled) }
                Text("One-time model downloads use the internet. Writing, semantic search, and English dictation work offline afterward. Other dictation languages are not yet included.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                HStack {
                    if models.preparing { Button("Cancel setup") { models.cancelSetup() }.buttonStyle(QuietButton()) }
                    else if models.ready { Button("Restart engines") { models.stop(); models.start() }.buttonStyle(QuietButton()).disabled(store.generating || store.dictation.busy) }
                    else { Button(models.installed ? "Start local models" : "Download & start · " + ByteCountFormatter.string(fromByteCount: models.totalModelBytes, countStyle: .file)) { models.start() }.buttonStyle(QuietButton(prominent: true)) }
                    Spacer()
                    Button("Open logs") { NSWorkspace.shared.open(AppPaths.support.appendingPathComponent("Logs")) }.buttonStyle(QuietButton())
                }
                Divider().overlay(Palette.line).padding(.vertical, 4)
                HStack { VStack(alignment: .leading, spacing: 5) { Text("Project library & backups").font(.system(size: 12)); Text("Automatic daily backups and recoverable revisions.").font(.system(size: 10)).foregroundStyle(Palette.secondary) }; Spacer(); Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.support) }.buttonStyle(QuietButton()) }
                Button("Recover projects from a library backup…") { store.chooseLibraryBackup() }.buttonStyle(QuietButton()).disabled(store.generating || store.dictation.busy)
                Text("Syllavane 0.11.0 · Local writing · Apple Silicon · Open-source application").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 10)
            } }.frame(height: min(500, max(300, (NSScreen.main?.visibleFrame.height ?? 850) - 210)))
        }.frame(width: 620)
    }
}
