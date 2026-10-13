import SwiftUI
import FolioCore

struct WorkspaceView: View {
    @ObservedObject var store: Workspace
    var body: some View {
        Group {
        if store.libraryVisible || store.project == nil { ProjectLibraryView(store: store) }
        else { HStack(spacing: 0) {
            if store.sidebarVisible && !store.focusMode { Sidebar(store: store).frame(width: 232)
            Rectangle().fill(Palette.line).frame(width: 1) }
            VStack(spacing: 0) {
                header
                if store.recoveredNarration != nil {
                    HStack { Label("An interrupted transcript is available.", systemImage: "waveform"); Spacer(); Button("Recover") { store.recoverNarration() }; Button("Dismiss") { store.clearRecoveredNarration() } }.font(.system(size: 11)).padding(12).background(Palette.tile)
                }
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack(spacing: 0) {
                    Group {
                        switch store.tab {
                        case .overview: ProjectOverviewView(store: store)
                        case .characters: CharactersView(store: store).id(store.projectID)
                        case .manuscript: WritingView(store: store, models: store.models, dictation: store.dictation)
                        case .map: StoryMapView(store: store)
                        case .sources: SourcesView(store: store)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !store.focusMode && store.inspector && store.tab == .manuscript {
                        Rectangle().fill(Palette.line).frame(width: 1)
                        Group { if store.project?.writingMode == .book { InspectorView(store: store) } else { WritingBriefView(store: store) } }.frame(width: 264)
                    }
                }
                statusBar
            }
        }
        } }
        .onReceive(store.models.$ready) { ready in if ready { store.analyzeSources() } }
        .background(Palette.background).foregroundStyle(Palette.text)
        .tint(Color(white: 0.75))
        .sheet(isPresented: $store.showSearch) { WritingSearch(store: store) }
        .sheet(isPresented: $store.showCompare) { RevisionComparison(store: store) }
        .sheet(isPresented: $store.showSettings) { SettingsView(store: store, models: store.models) }
        .onChange(of: store.showCharacters) { _, showing in if showing { store.tab = .characters; store.showCharacters = false } }
        .sheet(isPresented: Binding(get: { !store.pendingSources.isEmpty }, set: { _ in })) { SourceUseView(store: store) }
        .sheet(isPresented: $store.showNewProject) { NewProjectView(store: store) }
        .sheet(isPresented: $store.showHistory) { HistoryView(store: store) }
        .sheet(isPresented: $store.showBookPreview) { BookPreview(store: store) }
        .sheet(isPresented: $store.showStyle) { StyleView(store: store) }
        .sheet(isPresented: $store.showRelationship) { RelationshipView(store: store) }
        .alert("Syllavane", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                HStack(spacing: 12) { Image(systemName: "checkmark.circle"); Text(toast).font(.system(size: 12)); Button { store.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    .padding(14).background(Palette.hover).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line)).padding(.bottom, 44)
                    .task(id: toast) { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { store.toast = nil } }
            }
        }
    }
    private var header: some View {
        HStack(spacing: 18) {
            IconButton(icon: "sidebar.left", help: "Toggle projects sidebar") { withAnimation(.easeInOut(duration: 0.15)) { if store.focusMode { store.focusMode = false; store.sidebarVisible = true } else { store.sidebarVisible.toggle() } } }
            if !store.sidebarVisible { IconButton(icon: "plus", help: "New project") { store.showNewProject = true } }
            Text(store.project?.name ?? "Writing").font(.system(size: 13, weight: .medium))
            Spacer()
            if store.tab != .manuscript { Button("Back to writing") { store.tab = .manuscript }.buttonStyle(QuietButton()) }
            IconButton(icon: "magnifyingglass", help: "Search all writing · ⇧⌘F") { store.showSearch = true }
            IconButton(icon: store.focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", help: "Focus on writing · ⇧⌘L") { store.focusMode.toggle(); store.tab = .manuscript }
            Button { store.persistDraft(); store.flush(); store.showBookPreview = true } label: { Label("Preview", systemImage: "book") }.buttonStyle(QuietButton()).help("Preview and save a book PDF")
            Menu {
                Button("Write") { store.tab = .manuscript }
                Button("Project details") { store.tab = .overview }
                if store.project?.writingMode == .book {
                    Button("Characters") { store.tab = .characters }
                    Button("Story map") { store.tab = .map }
                }
                Button("Sources") { store.tab = .sources }
                Button("What I’ve learned") { store.showStyle = true }
                Divider()
                Button("Revision history") { store.loadHistory() }
                Button("Show story details") { store.inspector.toggle() }
                Button("Export manuscript…") { store.exportProject(manuscript: true) }
                Button("Export project backup…") { store.exportProject(manuscript: false) }
                Button("Settings…") { store.showSettings = true }
            } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.secondary) }.menuStyle(.borderlessButton).frame(width: 28).help("Project options")
        }.padding(.horizontal, 26).frame(height: 56)
    }
    private var statusBar: some View {
        HStack(spacing: 7) {
            Image(systemName: store.saved ? "checkmark" : "circle.dotted").font(.system(size: 9))
            Text(store.saved ? "Saved on this Mac" : "Saving…")
            Spacer()
            if !store.selectedText.isEmpty { Text("\(store.selectedText.split(whereSeparator: \.isWhitespace).count) words selected"); Text("·") }
            Text("\(store.project?.wordCount ?? 0) words")
            Text("·")
            Text("\(store.project?.chapters.count ?? 0) " + (store.project?.writingMode == .book ? "chapters" : "draft groups"))
        }.font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.horizontal, 24).frame(height: 30).background(Palette.sidebar).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

private struct Sidebar: View {
    @ObservedObject var store: Workspace
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); Image(systemName: "book.closed").font(.system(size: 12)); Text("SYLLAVANE").font(.system(size: 10, weight: .semibold)).tracking(3); Spacer() }.foregroundStyle(Palette.secondary).frame(height: 56).padding(.leading, 46)
            Button { store.showLibrary() } label: { Label("All projects", systemImage: "chevron.left").font(.system(size: 11)).foregroundStyle(Palette.secondary) }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 8)
            Button { store.showNewProject = true } label: { Label("New project", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(QuietButton()).padding(.horizontal, 14).padding(.top, 12)
            HStack { Eyebrow(text: "Projects"); Spacer() }.padding(.horizontal, 18).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(store.projects.sorted { $0.updatedAt > $1.updatedAt }) { project in
                        Button { store.selectProject(project.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: project.id == store.projectID ? "chevron.down" : "chevron.right").font(.system(size: 9))
                                Image(systemName: "folder").font(.system(size: 12))
                                Text(project.name).font(.system(size: 12)).lineLimit(1); Spacer()
                            }.foregroundStyle(project.id == store.projectID ? Palette.text : Palette.secondary).padding(10).background(project.id == store.projectID ? Palette.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                        if project.id == store.projectID {
                            ForEach(project.chapters) { chapter in
                                Button { if let id = chapter.scenes.last?.id { store.selectScene(id) } } label: {
                                    HStack(spacing: 8) { Image(systemName: "doc.text").font(.system(size: 10)); Text(chapter.title).font(.system(size: 11)).lineLimit(1); Spacer() }
                                    .foregroundStyle(store.chapter?.id == chapter.id ? Palette.text : Palette.secondary).padding(.vertical, 8).padding(.leading, 34).padding(.trailing, 8).background(store.chapter?.id == chapter.id ? Palette.tile : .clear).clipShape(RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(12)
            }
            Button { store.showSettings = true } label: { Label("Settings", systemImage: "gearshape").font(.system(size: 11)).foregroundStyle(Palette.secondary) }.buttonStyle(.plain).padding(22)
        }.background(Palette.sidebar)
    }
    private func sidebarAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9) }.buttonStyle(.plain)
    }
}

struct WritingView: View {
    @ObservedObject var store: Workspace
    @ObservedObject var models: LocalEngines
    @ObservedObject var dictation: Dictation
        @State private var feedbackExpanded = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Chapter title", text: Binding(get: { store.chapter?.title ?? "" }, set: { value in let id = store.chapter?.id; store.edit { p in if let i = p.chapters.firstIndex(where: { $0.id == id }) { p.chapters[i].title = value } } })).font(.system(size: 16, weight: .medium)).textFieldStyle(.plain)
                Spacer()
                if let latest = store.chapter?.scenes.last, latest.id != store.sceneID { Button("Latest") { store.selectScene(latest.id) }.buttonStyle(QuietButton()) }
                Text("\(store.chapter?.scenes.filter { !$0.text.isEmpty }.count ?? 0) accepted moments").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Button(store.project?.writingMode == .book ? "Finish chapter" : "Finish document") { store.finishChapter() }.buttonStyle(QuietButton()).disabled(store.generating || dictation.recording)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            ScrollViewReader { proxy in
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                chapterConversation
            if store.draftNeedsReview && !store.generating {
                VStack(alignment: .leading, spacing: 10) {
                    Label("This draft needs a closer look", systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .medium))
                    Text("Some wording may change your intent or leave your idea undeveloped. You can edit it directly or rebuild from your original narration.").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    Button("Rebuild from my narration") { store.regenerateDraft() }.buttonStyle(QuietButton()).help("Your current draft stays available until a replacement passes the checks")
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 24)
            }
            if !store.draftNotice.isEmpty { Text(store.draftNotice).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4).padding(.horizontal, 24).textSelection(.enabled) }
            if let draft = store.proposal, !draft.text.isEmpty {
                draftView(draft)
            } else {
                ZStack(alignment: .topLeading) {
                    ManuscriptEditor(text: Binding(get: { store.scene?.text ?? "" }, set: { value in store.updateManuscriptFromUser(value) }), onSelection: { text, range in store.selectedText = text; store.selection = range }, onRewrite: { instruction, remember in store.rewritePassage(instruction: instruction, remember: remember) }, canRewrite: !store.generating).id(store.sceneID)
                    if store.scene?.text.isEmpty != false {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(store.project?.writingMode == .book ? "A story begins with a thought." : "Start with an idea.").font(.system(size: 20, weight: .regular, design: .serif)).foregroundStyle(Color(white: 0.46))
                            Text("Speak your idea below, or start writing here.\nYou decide what to keep.").font(.system(size: 12)).lineSpacing(6).foregroundStyle(Palette.muted)
                            HStack(spacing: 16) { Label("Your voice", systemImage: "waveform"); if store.project?.writingMode == .book { Label("Your characters", systemImage: "person.2") }; Label("Your style", systemImage: "textformat") }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 14)
                        }.padding(.top, 28).padding(.leading, 8).allowsHitTesting(false)
                    }
                }.padding(.horizontal, 24).frame(height: 260)
            }
                Color.clear.frame(height: 1).id("latest")
            }.padding(.vertical, 12).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .onChange(of: store.sceneID) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            .onChange(of: store.scene?.conversation?.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            }
            composer.padding(.horizontal, 24).padding(.bottom, 14).padding(.top, 8)
        }
        .alert("Dictation", isPresented: Binding(get: { dictation.error != nil }, set: { if !$0 { dictation.error = nil } })) { Button("OK") { dictation.error = nil } } message: { Text(dictation.error ?? "") }
    }
    private var chapterConversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(visibleScenes) { scene in
                let turns = scene.conversation ?? legacyTurns(scene)
                if scene.id != store.sceneID && (!scene.text.isEmpty || scene.pendingDraft != nil) {
                    HStack { Text(scene.pendingDraft != nil ? "Draft awaiting review" : "Accepted writing").font(.system(size: 10)).foregroundStyle(Palette.secondary); Spacer(); Button("Open this moment") { store.selectScene(scene.id) }.buttonStyle(QuietButton()) }
                }
                ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                    if !(scene.id == store.sceneID && turn.kind == "draft" && index == turns.lastIndex(where: { $0.kind == "draft" }) && store.proposal != nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(turn.kind == "narration" ? "YOU · NARRATION" : turn.kind == "revision" ? "YOU · CHANGE REQUEST" : turn.kind == "decision" ? "MANUSCRIPT" : "DRAFT").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Palette.secondary)
                            if turn.kind == "draft" {
                                DisclosureGroup("Read this draft · \(turn.text.split(whereSeparator: \.isWhitespace).count) words") { Text(turn.text).font(.custom("Georgia", size: 15)).lineSpacing(6).textSelection(.enabled).padding(.top, 8) }.font(.system(size: 12))
                            } else { Text(turn.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(turn.kind == "draft" ? Palette.panel : Palette.tile).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }.padding(.horizontal, 24)
    }
    private var visibleScenes: [FolioCore.Scene] {
        guard let scenes = store.chapter?.scenes, let index = scenes.firstIndex(where: { $0.id == store.sceneID }) else { return [] }
        return Array(scenes.prefix(index + 1))
    }
    private func legacyTurns(_ scene: FolioCore.Scene) -> [WritingTurn] {
        var turns: [WritingTurn] = []
        if !scene.brief.isEmpty { turns.append(WritingTurn(kind: "narration", text: scene.brief)) }
        if let draft = scene.pendingDraft, !draft.isEmpty { turns.append(WritingTurn(kind: "draft", text: draft)) }
        else if !scene.text.isEmpty { turns.append(WritingTurn(kind: "draft", text: scene.text)); turns.append(WritingTurn(kind: "decision", text: "In your manuscript")) }
        return turns
    }
    private func draftView(_ draft: DraftProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Image(systemName: "sparkle"); Text("Your draft" + ((store.project?.authorEdits?.isEmpty == false || store.project?.approvedRewrites?.isEmpty == false) ? " · learning from your edits" : "")).font(.system(size: 11, weight: .medium)); Spacer(); if store.generating { ProgressView().controlSize(.mini) } }.foregroundStyle(Palette.secondary).padding(.bottom, 14)
            ManuscriptEditor(text: Binding(get: { store.proposal?.text ?? "" }, set: { value in store.updateDraftFromUser(value) }), onSelection: { text, range in store.draftSelectedText = text; store.draftSelection = range }, onRewrite: { instruction, remember in store.rewritePassage(instruction: instruction, remember: remember) }, canRewrite: !store.generating, changeID: store.changePulse, changedRange: store.changedRange, growWithText: true)
            if store.revisionBefore != nil {
                HStack {
                    Label("Passage updated", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button("Compare") { store.showCompare = true }.buttonStyle(QuietButton())
                    Button("Undo change") { store.undoAIRevision() }.buttonStyle(QuietButton()).disabled(store.generating || store.proposal?.text != store.revisionAfter)
                    Button("Keep change") { store.keepAIRevision() }.help("Remember this approved rewrite as a style example for this project").buttonStyle(QuietButton())
                }.padding(.vertical, 8)
            }
            Text(store.draftSelectedText.isEmpty ? "Edit directly, or tell Syllavane what to change below." : "Your feedback will change only the highlighted passage.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            DisclosureGroup("Type a change or choose an adjustment", isExpanded: $feedbackExpanded) {
            HStack {
                TextField("What doesn’t feel right?", text: $store.feedback, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...3)
                Button { store.toggleDictation(revision: true) } label: { Image(systemName: "mic") }.buttonStyle(QuietButton()).help("Dictate changes to this draft").disabled(store.generating || dictation.busy)
                Menu { ForEach(DraftAdjustments.all, id: \.0) { item in Button(item.0) { store.generate(instruction: item.1) } } } label: { Image(systemName: "slider.horizontal.3") }.menuStyle(.borderlessButton).fixedSize().help("Adjust the whole draft or highlighted passage").disabled(store.generating)
                Button("Revise draft") { store.applyFeedback() }.buttonStyle(QuietButton()).disabled(store.feedback.isEmpty || store.generating)
            }.padding(12).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.top, 8)
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 8)
            HStack {
                Menu {
                    Button("Start again from narration") { store.regenerateDraft() }
                    Button("Copy draft") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft.text, forType: .string) }
                    Button("Discard draft") { store.discardDraft() }
                } label: { Text("Draft options") }.menuStyle(.borderlessButton).fixedSize().disabled(store.generating)
                Spacer()
                if store.generating { Button("Stop") { store.cancelGeneration() }.buttonStyle(QuietButton()) }
                Button("Accept draft") { store.acceptDraft() }.buttonStyle(QuietButton(prominent: true)).disabled(store.generating || draft.text.isEmpty)
            }.padding(.top, 16)
        }.padding(20).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line)).padding(.horizontal, 24)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) { Avatar(data: store.project?.assistantAvatar, name: "S", size: 22); Text(store.dictateRevision ? "Tell me what to change" : (store.project?.writingMode == .book ? "Describe your idea" : "Describe your idea")).font(.system(size: 11, weight: .medium)) }
                Spacer()
                if !models.ready {
                    Button { store.showSettings = true } label: { HStack(spacing: 5) { if models.preparing { ProgressView().controlSize(.mini) }; Text(models.preparing ? "Starting models…" : "Set up local AI").font(.system(size: 10)) } }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                } else { Text(store.draftAfterSpeaking ? "Stop speaking to create your draft" : "Your words are saved when you stop").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
            }.padding(.horizontal, 15).padding(.top, 13)
            if dictation.recording || dictation.transcribing {
                HStack(spacing: 10) {
                    HStack(spacing: 3) { ForEach(0..<12) { i in Capsule().fill(Color(white: 0.6)).frame(width: 3, height: CGFloat(5 + Float((i * 7) % 15) * max(0.2, dictation.level * 4))).animation(.easeOut(duration: 0.1), value: dictation.level) } }.frame(width: 70, height: 30)
                    Text(dictation.transcribing ? "Finishing transcription…" : "Listening · \(dictation.seconds / 60):\(String(format: "%02d", dictation.seconds % 60))").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Spacer()
                    if dictation.recording { Button("Cancel") { dictation.discard(); store.clearRecoveredNarration(); store.dictateRevision = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                }.padding(.horizontal, 16).padding(.top, 10)
                Text(dictation.preview.isEmpty ? "Speak naturally. Pause whenever you need." : dictation.preview).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(4).frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading).padding(15)
            } else {
                TextField(store.project?.writingMode.placeholder ?? "Tell me what to write…", text: Binding(get: { store.proposal != nil ? store.continuationText : (store.scene?.brief ?? "") }, set: { value in if store.proposal != nil { store.continuationText = value } else { store.editScene { $0.brief = value } } }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineSpacing(4).lineLimit(1...4).padding(15)
                    .disabled(store.generating)
                    .onSubmit { if let brief = store.scene?.brief, brief.hasPrefix("/") || brief.hasPrefix("#scene") { _ = store.runCommand(brief) } }
            }
            HStack(spacing: 7) {
                Menu {
                    Button("Add or develop a character") { store.showCharacters = true }
                    Button("Clean up dictation") { store.cleanBrief() }
                    Toggle("Create a draft when I stop speaking", isOn: $store.draftAfterSpeaking)
                    Toggle("Recognize spoken commands", isOn: $store.commandMode)
                    Button("Run typed command") { if let brief = store.scene?.brief { if !store.runCommand(brief) { store.toast = "Use /character, #scene, or start chapter…" } } }
                    if dictation.lastRecording != nil { Button("Retry last transcription") { store.retryDictation() } }
                } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 20) }.menuStyle(.borderlessButton).frame(width: 25)
                Spacer(minLength: 4)
                if store.generating && store.proposal?.text.isEmpty != false { Button { store.cancelGeneration() } label: { Image(systemName: "stop.fill") }.buttonStyle(QuietButton()).help("Stop") }
                Button { if !dictation.recording { store.dictateRevision = false }; store.toggleDictation() } label: { Label(dictation.recording ? "Finish speaking" : "Speak", systemImage: dictation.recording ? "stop.fill" : "mic.fill").font(.system(size: 13, weight: .medium)) }.buttonStyle(QuietButton(prominent: true)).disabled(dictation.starting || dictation.transcribing || (store.generating && !dictation.recording)).help("Start or stop dictation · ⇧⌘D").accessibilityLabel(dictation.recording ? "Finish speaking" : "Speak")
                if !(store.proposal != nil ? store.continuationText : (store.scene?.brief ?? "")).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Button { store.submitNarration() } label: { HStack(spacing: 8) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)) } }.buttonStyle(QuietButton()).disabled(store.generating || dictation.recording || dictation.transcribing || (store.proposal != nil ? store.continuationText : (store.scene?.brief ?? "")).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Send your idea").accessibilityLabel("Send your idea") }
            }.padding(.horizontal, 12).padding(.bottom, 12)
            if !store.activity.isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    HStack { Text(store.activity); if let start = store.revisionStarted { Text("· " + String(Int(tick.date.timeIntervalSince(start))) + "s") }; Spacer(); ProgressView().controlSize(.mini) }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.padding(.horizontal, 15).padding(.bottom, 10)
            }
        }.background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.2)))
    }
}
