import SwiftUI
import FolioCore

struct InspectorView: View {
    @ObservedObject var store: Workspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack { Eyebrow(text: "Story details"); Spacer(); Image(systemName: "square.stack").foregroundStyle(Palette.muted).font(.system(size: 12)) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Eyebrow(text: "In this scene"); Spacer(); Button { store.showCharacters = true } label: { Image(systemName: "plus").font(.system(size: 11)) }.buttonStyle(.plain).help("Manage characters") }
                    let characters = store.project?.characters.filter { character in (store.scene?.characterIDs.contains(character.id) ?? false) || CharacterMatcher.mentions(character, in: (store.scene?.brief ?? "") + " " + (store.scene?.text ?? "")) } ?? []
                    if !store.memoryStatus.isEmpty { Text(store.memoryStatus).font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                if characters.isEmpty { Text("Mention a character in your scene brief, or add one with /character.").font(.system(size: 11)).lineSpacing(5).foregroundStyle(Palette.muted) }
                    ForEach(characters) { character in
                        Button { store.characterSearch = character.name; store.showCharacters = true } label: {
                            HStack(spacing: 10) { Avatar(data: character.avatar, name: character.name); VStack(alignment: .leading, spacing: 4) { Text(character.name).font(.system(size: 12, weight: .medium)); Text((character.traits ?? []).first(where: { !$0.value.isEmpty }).map { "\($0.category): \($0.value)" } ?? (character.details.isEmpty ? "Add character details" : character.details)).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(2) }; Spacer() }.padding(10).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Divider().overlay(Palette.line)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Eyebrow(text: "Your voice"); Spacer(); Button("Edit") { store.showStyle = true }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.secondary) }
                    Text(store.project?.style.isEmpty == false ? store.project!.style : (store.project?.sources.filter(\.isStyleSample).compactMap { $0.analysis?.guide }.joined(separator: "\n").isEmpty == false ? "Voice learned from this book’s sources. Open Voice & style to review the scene craft and guidance." : "Add a writing sample or describe your style. Syllavane keeps your voice close.")).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(5).lineLimit(6)
                    Button { store.importSources() } label: { Label("Add writing sample", systemImage: "plus") }.buttonStyle(QuietButton())
                }
                if !store.references.isEmpty {
                    Divider().overlay(Palette.line)
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Context used")
                        ForEach(store.references) { ref in DisclosureGroup { Text(ref.text).font(.system(size: 10)).lineSpacing(4).foregroundStyle(Palette.secondary).textSelection(.enabled) } label: { Label(ref.label, systemImage: ref.isStyle ? "text.quote" : "doc.text").font(.system(size: 10)).lineLimit(1) } }
                    }
                }
            }.padding(20)
        }.background(Palette.sidebar)
    }
}

struct SourcesView: View {
    @ObservedObject var store: Workspace
    @State private var selected: UUID?
    @State private var pasteSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 8) { Eyebrow(text: store.project?.name ?? "Project"); Text("The source of your voice.").font(.system(size: 29, design: .serif)); Text("Your scene craft, with examples from your writing.").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                Spacer()
                Menu {
                    Button("My writing · learn my style") { store.importSources() }
                    Button("Reference material · facts only") { store.importSources(asStyleSample: false) }
                    Divider(); Button("Paste writing…") { pasteSource = true }
                } label: { Label("Import source", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
            }
            if store.project?.sources.isEmpty != false {
                EmptyHint(icon: "doc.text", title: "Bring your writing.", detail: "Import TXT, Markdown, PDF, RTF, or DOCX. Use your own scenes as style samples; keep research as reference material.")
            } else {
                HStack(alignment: .top, spacing: 18) {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.project?.sources ?? []) { source in
                                Button { selected = source.id } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label(source.name, systemImage: "doc.text").font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Text(source.isStyleSample ? "Writing style" : "Reference only").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                        if store.analysisBusy.contains(source.id) { Text("Reading scene craft…").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                                        else { Text(source.analysis == nil ? "Analysis pending" : "Style observations ready").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background((selected ?? store.project?.sources.first?.id) == source.id ? Palette.hover : Palette.tile).clipShape(RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(width: 210)
                    if let source = store.project?.sources.first(where: { $0.id == selected }) ?? store.project?.sources.first {
                        sourceDetail(source)
                    }
                }
            }
            Text("Analysis describes the writing, not the author's personality. You can correct every observation.").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(30).onAppear { store.analyzeSources() }.sheet(isPresented: $pasteSource) { PasteSourceView(store: store, close: { pasteSource = false }) }
    }
    private func sourceDetail(_ source: Source) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Toggle("Use this voice when writing", isOn: Binding(get: { source.isStyleSample }, set: { value in store.edit { p in if let i = p.sources.firstIndex(where: { $0.id == source.id }) { p.sources[i].isStyleSample = value; if p.sources[i].continued != true { p.sources[i].use = value ? .style : .reference } } }; store.flush(reason: "Source role changed") })).font(.system(size: 11)).toggleStyle(.checkbox)
                    Spacer()
                    Button("Remove") { store.flush(reason: "Before removing source"); store.edit { $0.sources.removeAll { $0.id == source.id } }; store.flush(reason: "Source removed") }.buttonStyle(QuietButton()).help("Remove from this project; original file is kept")
                }
                let measurements = WritingMeasurements(source.text)
                if source.continued != true { Button("Continue writing from this source") { store.continueExistingSource(source.id) }.buttonStyle(QuietButton()) }
                else { Label("Included in your manuscript", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                Text("\(measurements.words) words · \(measurements.paragraphs) paragraphs · ~\(measurements.averageSentenceWords) words per sentence").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                HStack { Eyebrow(text: "How this writing works"); Spacer(); if store.analysisBusy.contains(source.id) { ProgressView().controlSize(.small) }; Button(source.analysis == nil ? "Analyze" : "Analyze again") { store.analyzeSources(force: true, sourceID: source.id) }.buttonStyle(QuietButton()).disabled(store.analysisBusy.contains(source.id)) }
                if let analysis = source.analysis {
                    ForEach(analysis.observations) { observation in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(observation.dimension).font(.system(size: 13, weight: .medium))
                            TextField("Observation", text: Binding(get: { observation.observation }, set: { value in
                                store.edit { p in if let si = p.sources.firstIndex(where: { $0.id == source.id }), let oi = p.sources[si].analysis?.observations.firstIndex(where: { $0.id == observation.id }) { p.sources[si].analysis?.observations[oi].observation = value } }
                            }), axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4).accessibilityLabel("Observation: " + observation.dimension)
                            Text("“\(observation.evidence)”").font(.system(size: 13, design: .serif)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                            TextField("How Syllavane should apply this", text: Binding(get: { observation.guidance }, set: { value in
                                store.edit { p in if let si = p.sources.firstIndex(where: { $0.id == source.id }), let oi = p.sources[si].analysis?.observations.firstIndex(where: { $0.id == observation.id }) { p.sources[si].analysis?.observations[oi].guidance = value } }
                            }), axis: .vertical).font(.system(size: 12)).textFieldStyle(.plain).lineLimit(2...5).padding(10).background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Writing guidance: " + observation.dimension)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    Text(source.isStyleSample ? "This guidance and relevant original excerpts accompany each draft. Your own voice instructions take priority." : "Reference only: this source’s style is excluded from drafts.").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
                } else { Text(store.analysisBusy.contains(source.id) ? "Reading scene construction, inner experience, rhythm, dialogue, and imagery locally…" : "Choose Analyze to read this source. Syllavane will ask you to start local models if needed.").font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5) }
                if let error = store.analysisErrors[source.id] { Text(error).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                DisclosureGroup("Original source") { Text(source.text).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10) }.font(.system(size: 12))
            }.padding(20)
        }.background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StoryMapView: View {
    @ObservedObject var store: Workspace
    @State private var focused: UUID?
    @State private var editingRelationship: UUID?
    @State private var relationshipLabel = ""
    private var characters: [StoryCharacter] { store.project?.characters ?? [] }
    private var scenes: [FolioCore.Scene] { store.project?.scenes.filter { !$0.brief.isEmpty || !$0.text.isEmpty } ?? [] }
    private func involved(_ scene: FolioCore.Scene) -> [StoryCharacter] { characters.filter { scene.characterIDs.contains($0.id) || CharacterMatcher.mentions($0, in: scene.brief + " " + scene.text) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) { Eyebrow(text: "Story memory"); Text("The threads between people.").font(.system(size: 29, design: .serif)); Text("Connections from your narration. Moments from your manuscript.").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                    Spacer()
                    Button(store.memoryBusy ? "Reading…" : "Read narration") { store.extractMemory() }.buttonStyle(QuietButton()).disabled(store.memoryBusy)
                    Button { store.showRelationship = true } label: { Image(systemName: "plus") }.buttonStyle(QuietButton()).disabled(characters.count < 2)
                }
                if !store.memoryStatus.isEmpty { Text(store.memoryStatus).font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                if characters.isEmpty {
                    EmptyHint(icon: "person.2", title: "People emerge as you narrate.", detail: "Describe who they are to one another. Syllavane will add evidence-backed connections after reading your narration.").frame(height: 220)
                } else {
                    GeometryReader { geometry in
                        let center = CGPoint(x: geometry.size.width / 2, y: 155)
                        let radius = min(geometry.size.width / 2 - 100, 106)
                        ZStack {
                            Canvas { context, _ in
                                for edge in store.project?.relationships ?? [] {
                                    if let from = characters.firstIndex(where: { $0.id == edge.from }), let to = characters.firstIndex(where: { $0.id == edge.to }) {
                                        let a = point(from, center, radius), b = point(to, center, radius)
                                        var path = Path(); path.move(to: a); path.addLine(to: b)
                                        context.stroke(path, with: .color(Color(white: 0.4)), style: StrokeStyle(lineWidth: 1, dash: edge.inferred == true ? [5, 4] : []))
                                        let labelPoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 12)
                                        context.draw(Text(edge.label).font(.system(size: 9)).foregroundColor(Color(white: 0.7)), at: labelPoint)
                                        let angle = atan2(b.y - a.y, b.x - a.x)
                                        let tip = CGPoint(x: b.x - cos(angle) * 48, y: b.y - sin(angle) * 48)
                                        var arrow = Path(); arrow.move(to: CGPoint(x: tip.x - cos(angle - 0.5) * 8, y: tip.y - sin(angle - 0.5) * 8)); arrow.addLine(to: tip); arrow.addLine(to: CGPoint(x: tip.x - cos(angle + 0.5) * 8, y: tip.y - sin(angle + 0.5) * 8)); context.stroke(arrow, with: .color(Color(white: 0.5)), lineWidth: 1)
                                    }
                                }
                            }
                            ForEach(Array(characters.enumerated()), id: \.element.id) { index, character in
                                Button { focused = focused == character.id ? nil : character.id } label: {
                                    HStack(spacing: 9) { Avatar(data: character.avatar, name: character.name, size: 28); Text(character.name).font(.system(size: 12, weight: .medium)) }.padding(10).background(focused == character.id ? Palette.hover : Palette.tile).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
                                }.buttonStyle(.plain).position(point(index, center, radius))
                            }
                        }
                    }.frame(height: 310).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                ForEach((store.project?.relationships ?? []).filter { focused == nil || $0.from == focused || $0.to == focused }) { edge in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: edge.inferred == true ? "sparkle" : "link").foregroundStyle(Palette.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(characters.first { $0.id == edge.from }?.name ?? "") → \(characters.first { $0.id == edge.to }?.name ?? "")").font(.system(size: 12, weight: .medium))
                            Text(edge.label).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            if let evidence = edge.evidence { Text("“\(evidence)”").font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(3) }
                            if edge.inferred == true { Text("Inferred from narration · review or correct").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                        }
                        Spacer()
                        Button("Edit") { editingRelationship = edge.id; relationshipLabel = edge.label }.buttonStyle(QuietButton())
                        Button { store.flush(reason: "Before removing connection"); store.edit { $0.relationships.removeAll { $0.id == edge.id } }; store.flush() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Remove connection")
                    }.padding(14).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 9))
                }
                HStack { Eyebrow(text: "Moments"); Spacer(); if focused != nil { Button("Show everyone") { focused = nil }.buttonStyle(QuietButton()) } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(scenes.filter { focused == nil || involved($0).contains { $0.id == focused } }) { scene in
                        Button { store.selectScene(scene.id) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Image(systemName: "text.alignleft").foregroundStyle(Palette.secondary); Text(scene.title == "Continue narration" || scene.title == "Untitled scene" ? "Moment \((store.project?.scenes.firstIndex { $0.id == scene.id } ?? 0) + 1)" : scene.title).font(.system(size: 12, weight: .medium)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                                Text(scene.brief.isEmpty ? scene.text : scene.brief).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 6) { ForEach(involved(scene)) { character in HStack(spacing: 4) { Avatar(data: character.avatar, name: character.name, size: 18); Text(character.name).font(.system(size: 9)) }.padding(4).background(Palette.hover).clipShape(RoundedRectangle(cornerRadius: 5)) } }
                                    Text(involved(scene).map(\.name).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(30)
        }
        .sheet(isPresented: Binding(get: { editingRelationship != nil }, set: { if !$0 { editingRelationship = nil } })) {
            SheetShell(title: "Refine this connection.", subtitle: "Your correction becomes the confirmed relationship.", close: { editingRelationship = nil }) {
                PanelField(title: "Relationship", placeholder: "How are they connected?", value: $relationshipLabel)
                Button("Save connection") { let id = editingRelationship; store.edit { p in if let index = p.relationships.firstIndex(where: { $0.id == id }) { p.relationships[index].label = relationshipLabel; p.relationships[index].inferred = false } }; store.flush(reason: "Connection corrected"); editingRelationship = nil }.buttonStyle(QuietButton(prominent: true))
            }.frame(width: 500)
        }
    }
    private func point(_ index: Int, _ center: CGPoint, _ radius: CGFloat) -> CGPoint {
        let angle = Double(index) / Double(max(characters.count, 1)) * 2 * Double.pi - Double.pi / 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

struct WritingBriefView: View {
    @ObservedObject var store: Workspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Eyebrow(text: store.project?.writingMode.title ?? "Writing")
                Text(store.project?.writingMode.guidance ?? "").font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.secondary)
                if store.project?.writingMode == .social { Text("\(store.proposal?.text.count ?? store.scene?.text.count ?? 0) / 280 characters").font(.system(size: 12)).monospacedDigit() }
                PanelField(title: "Audience", placeholder: "Who are you writing for?", value: Binding(get: { store.project?.audience ?? "" }, set: { value in store.edit { $0.audience = value } }), lines: 2)
                Button("Sources & evidence") { store.tab = .sources }.buttonStyle(QuietButton())
                Button("Voice & preferences") { store.showStyle = true }.buttonStyle(QuietButton())
                Eyebrow(text: "Refine the draft")
                ForEach([("Make it clearer", "Explain the same meaning more clearly; invent no facts."), ("Make it concise", "Remove repetition and shorten the writing while keeping its main points."), ("Closer to my voice", "Follow my source writing's rhythm and tone, preserving the supplied facts.")], id: \.0) { item in Button(item.0) { store.generate(instruction: item.1) }.buttonStyle(QuietButton()).disabled(store.generating) }
                TextField("What should change?", text: $store.feedback, axis: .vertical).font(.system(size: 12)).textFieldStyle(.plain).lineLimit(2...5).padding(12).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Apply feedback") { store.applyFeedback() }.buttonStyle(QuietButton()).disabled(store.feedback.isEmpty || store.generating)
                if !store.references.isEmpty { Eyebrow(text: "Context used"); ForEach(store.references) { ref in DisclosureGroup(ref.label) { Text(ref.text).font(.system(size: 11)).textSelection(.enabled) }.font(.system(size: 11)) } }
            }.padding(20)
        }.background(Palette.sidebar)
    }
}
