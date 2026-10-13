import XCTest
import PDFKit
@testable import FolioCore

final class FolioCoreTests: XCTestCase {
    func testUnifiedSearchRoutesNarrationCharactersAndSources() {
        var p = StoryProject(name: "North")
        p.chapters[0].scenes[0].brief = "Joseph waits for George."
        p.characters = [StoryCharacter(name: "Joseph", details: "Quiet")]
        p.sources = [Source(name: "Notes", text: "Joseph returns")]
        let hits = LibrarySearch.find("Joseph", projects: [p])
        XCTAssertEqual(Set(hits.map(\.kind)), Set(["Writing", "Character", "Source"]))
        XCTAssertEqual(hits.first(where: { $0.kind == "Writing" })?.sceneID, p.scenes[0].id)
        XCTAssertEqual(hits.first(where: { $0.kind == "Character" })?.characterName, "Joseph")
        XCTAssertTrue(LibrarySearch.find("   ", projects: [p]).isEmpty)
        XCTAssertTrue(LibrarySearch.find("missing", projects: [p]).isEmpty)
    }
    func testArticlePDFUsesA4AndPreservesEnding() throws {
        var p = StoryProject(name: "An article"); p.mode = .blog
        p.chapters[0].scenes[0].text = "Opening idea.\n\nAn unmistakable ending."
        let doc = try XCTUnwrap(PDFDocument(data: BookPDF.render(project: p)))
        XCTAssertEqual(doc.pageCount, 1)
        XCTAssertEqual(doc.page(at: 0)?.bounds(for: .mediaBox).width, 595)
        XCTAssertTrue(doc.string?.contains("An unmistakable ending.") == true)
    }
    func testConversationSurvivesProjectRoundTripAndLegacyScenesLoad() throws {
        var p = StoryProject(name: "Conversation")
        let first = "Joseph stays silent."
        p.chapters[0].scenes[0].conversation = [WritingTurn(kind: "narration", text: first), WritingTurn(kind: "draft", text: "Joseph said nothing."), WritingTurn(kind: "revision", text: "Less descriptive"), WritingTurn(kind: "draft", text: "Joseph was silent.")]
        let data = try JSONEncoder().encode(p)
        let restored = try JSONDecoder().decode(StoryProject.self, from: data)
        XCTAssertEqual(restored.scenes[0].conversation, p.scenes[0].conversation)
        XCTAssertEqual(restored.scenes[0].conversation?.map(\.kind), ["narration", "draft", "revision", "draft"])
        let old = try JSONEncoder().encode(Scene())
        let scene = try JSONDecoder().decode(Scene.self, from: old)
        XCTAssertNil(scene.conversation)
    }
    func testNamesRespectWordBoundariesAndAliases() {
        var ann = StoryCharacter(name: "Ann"); ann.aliases = ["Annie"]
        XCTAssertFalse(CharacterMatcher.mentions(ann, in: "Joanna opens the door."))
        XCTAssertTrue(CharacterMatcher.mentions(ann, in: "ANN turns to Annie."))
        XCTAssertEqual(CharacterMatcher.canonicalize("Annie, look at Joanna.", characters: [ann]), "Ann, look at Joanna.")
        XCTAssertEqual(CharacterMatcher.suggestions(for: "An", in: [ann]).count, 1)
    }
    func testAmbiguousAliasIsNotSilentlyReplaced() {
        var one = StoryCharacter(name: "Arjun"); one.aliases = ["AJ"]
        var two = StoryCharacter(name: "Ajay"); two.aliases = ["AJ"]
        XCTAssertEqual(CharacterMatcher.canonicalize("AJ arrives.", characters: [one, two]), "AJ arrives.")
    }
    func testFutureDevelopmentCannotLeakIntoEarlierScene() {
        var p = StoryProject(); let first = p.scenes[0].id
        let second = Scene(title: "Later"); p.chapters[0].scenes.append(second)
        var c = StoryCharacter(name: "Mira", details: "Trusting")
        c.developments = [Development(sceneID: second.id, note: "Distrusts her brother")]; p.characters = [c]
        XCTAssertFalse(p.characterContext(at: first, mentions: "Mira").contains("Distrusts"))
        XCTAssertTrue(p.characterContext(at: second.id, mentions: "Mira").contains("Distrusts"))
    }
    func testOnlyExplicitCommandsChangeStructure() {
        XCTAssertEqual(VoiceCommand.parse("Start chapter two."), .chapter("Chapter two"))
        XCTAssertEqual(VoiceCommand.parse("He says chapter two was strange."), .dictation("He says chapter two was strange."))
        XCTAssertEqual(VoiceCommand.parse("/character Mira"), .character("Mira"))
        XCTAssertEqual(VoiceCommand.parse("tone down"), .rewrite("tone down"))
    }
    func testRetrievalDoesNotUseFutureScenes() {
        var p = StoryProject(); p.chapters[0].scenes[0].text = "Earlier"
        let second = Scene(title: "Second"); p.chapters[0].scenes.append(second)
        var future = Scene(title: "Future"); future.text = "Spoiler"
        p.chapters[0].scenes.append(future)
        let passages = Retrieval.passages(project: p, before: second.id)
        XCTAssertEqual(passages.map(\.text), ["Earlier"])
        XCTAssertEqual(Retrieval.cosine([1, 0], [0, 1]), 0)
    }
    func testDatabasePersistenceRevisionsAndBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try ProjectDatabase(url: folder.appendingPathComponent("library.sqlite"))
        var p = StoryProject(name: "A 'quoted' story"); p.chapters[0].scenes[0].text = "Before"
        try db.save(p, reason: "Original")
        p.chapters[0].scenes[0].text = "After"; try db.save(p, reason: "Edit")
        XCTAssertEqual(try db.projects().first?.scenes.first?.text, "After")
        XCTAssertEqual(try db.revisions(projectID: p.id).last?.project.scenes.first?.text, "Before")
        try db.saveEmbedding(key: "test", vector: [0.1, 0.5]); XCTAssertEqual(try db.embedding(key: "test"), [0.1, 0.5])
        try db.backup(to: folder.appendingPathComponent("backup.sqlite"))
        let backup = try ProjectDatabase(url: folder.appendingPathComponent("backup.sqlite"))
        XCTAssertEqual(try backup.projects().first?.name, p.name)
    }
    func testInvalidImportRejected() {
        var p = StoryProject(); p.chapters = []
        XCTAssertThrowsError(try p.validate())
    }
    func testDraftRevisionPreservesUnselectedParagraphs() throws {
        let original = "First paragraph.\n\nShe felt nothing.\n\nLast paragraph."
        let range = (original as NSString).range(of: "She felt nothing.")
        XCTAssertEqual(try DraftEditing.replacing(original, range: range, with: "Her hands would not settle."), "First paragraph.\n\nHer hands would not settle.\n\nLast paragraph.")
        XCTAssertThrowsError(try DraftEditing.replacing(original, range: NSRange(location: 9999, length: 4), with: "bad"))
    }
    func testNarrationMemoryRequiresEvidence() throws {
        var project = StoryProject()
        let sceneID = project.scenes[0].id
        let extraction = try MemoryExtraction.decode(#"{"characters":[{"name":"Mira","evidence":"Mira meets her father Dev."},{"name":"Dev","evidence":"Mira meets her father Dev."},{"name":"Ghost","evidence":"Invented quotation"}],"relationships":[{"from":"Mira","to":"Dev","label":"daughter of","evidence":"Mira meets her father Dev."},{"from":"Dev","to":"Mira","label":"hates","evidence":"invented"}]}"#)
        extraction.apply(to: &project, sceneID: sceneID, narration: "Mira meets her father Dev.")
        XCTAssertEqual(project.characters.count, 2)
        XCTAssertEqual(project.relationships.count, 1)
        XCTAssertEqual(project.relationships[0].inferred, true)
        XCTAssertEqual(project.relationships[0].sourceSceneID, sceneID)
    }
    func testContinuousExportAndPendingDraftRecovery() throws {
        var project = StoryProject()
        project.chapters[0].scenes[0].text = "First passage."
        var second = Scene(); second.text = "Second passage."; second.pendingDraft = "Still being revised."
        project.chapters[0].scenes.append(second)
        let decoded = try JSONDecoder().decode(StoryProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.scenes.last?.pendingDraft, "Still being revised.")
        XCTAssertTrue(project.markdown().contains("First passage.\n\nSecond passage."))
        XCTAssertFalse(project.markdown().contains("###"))
        XCTAssertEqual(VoiceCommand.parse("Finish this chapter."), .chapter(""))
    }

    func testExplicitKinshipIsFoundWithoutModelGuessing() {
        var p = StoryProject()
        let text = "Mira meets her father Dev after ten years."
        MemoryExtraction.explicitConnections(in: text).apply(to: &p, sceneID: p.scenes[0].id, narration: text)
        XCTAssertEqual(p.characters.map(\.name), ["Mira", "Dev"])
        XCTAssertEqual(p.relationships.first?.label, "Dev is Mira’s father")
        XCTAssertEqual(MemoryExtraction.explicitConnections(in: "Mira sits next to Dev.").relationships.count, 0)
    }

    func testStyleAnalysisRejectsUnsupportedQuotesAndReferenceStyle() throws {
        let sourceText = "She folded the letter. She did not look up."
        let json = #"{"observations":[{"dimension":"Inner experience","observation":"Emotion appears through actions.","evidence":"She did not look up.","guidance":"Show hesitation through withheld actions."},{"dimension":"Imagery & detail","observation":"Lush imagery.","evidence":"The purple sky","guidance":"Use purple skies."}]}"#
        let analysis = try StyleAnalysis.decode(json, source: sourceText)
        XCTAssertEqual(analysis.observations.count, 1)
        var source = Source(name: "Sample", text: sourceText); source.analysis = analysis
        var project = StoryProject(); project.sources = [source]
        XCTAssertTrue(PromptBuilder.system(project: project).contains("withheld actions"))
        project.sources[0].isStyleSample = false
        XCTAssertFalse(PromptBuilder.system(project: project).contains("withheld actions"))
        XCTAssertThrowsError(try StyleAnalysis.decode(json, source: "Unrelated writing."))
    }
    func testTraitsPersistAndStayWithinProject() throws {
        var book = StoryProject(name: "One")
        var character = StoryCharacter(name: "Ada"); character.traits = [CharacterTrait(category: "Fear", value: "Being forgotten")]
        book.characters = [character]
        let decoded = try JSONDecoder().decode(StoryProject.self, from: JSONEncoder().encode(book))
        XCTAssertTrue(decoded.characterContext(at: decoded.scenes[0].id, mentions: "Ada").contains("Fear: Being forgotten"))
        let other = StoryProject(name: "Two")
        XCTAssertFalse(other.characterContext(at: other.scenes[0].id, mentions: "Ada").contains("Being forgotten"))
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as! [String: Any]
        var people = legacy["characters"] as! [[String: Any]]; people[0].removeValue(forKey: "traits"); legacy["characters"] = people
        let old = try JSONDecoder().decode(StoryProject.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.characters[0].traits)
    }
    func testTranscriptFilteringPreservesNarrativeMeaning() {
        XCTAssertEqual(TranscriptFilter.clean("[BLANK_AUDIO] (coughing)"), "")
        XCTAssertEqual(TranscriptFilter.clean("Um, Mira waits. [breathing] Uh, she sighs."), "Mira waits. she sighs.")
        XCTAssertEqual(TranscriptFilter.clean("She heard music. The room hummed. She sighed."), "She heard music. The room hummed. She sighed.")
        XCTAssertEqual(TranscriptFilter.clean("Um, yes.", removeFillers: false), "Um, yes.")
        XCTAssertFalse(TranscriptFilter.hasVoiceEnergy(Data(repeating: 0, count: 32000)))
        var click = Data(repeating: 0, count: 32000); click[200] = 255; click[201] = 127
        XCTAssertFalse(TranscriptFilter.hasVoiceEnergy(click))
        var voice = Data()
        for i in 0..<16000 { var value = Int16(sin(Double(i) * 0.08) * 4000).littleEndian; withUnsafeBytes(of: &value) { voice.append(contentsOf: $0) } }
        XCTAssertTrue(TranscriptFilter.hasVoiceEnergy(voice))
    }

    func testCopiedNarrationTriggersRetry() {
        let notes = "Mira waits outside the library. She takes out her phone then puts it away. Stop there."
        XCTAssertTrue(DraftQuality.echoesNarration(notes, narration: notes))
        XCTAssertFalse(DraftQuality.echoesNarration("The library windows were dark. Mira touched the phone through her coat pocket, rehearsing a greeting she would never use.", narration: notes))
    }

    func testJosephRegressionRejectsUnrelatedScene() {
        let notes = "The next day Joseph couldn't understand what happened yesterday and how he should react. He doesn't talk to his father George for many days, until his mother's death anniversary."
        let wrong = "Joseph's eyes turned moist. There were four people present, all smiling at the fire. George stood nearby. Joseph gripped the steering wheel."
        let issues = GroundingCheck.issues(draft: wrong, narration: notes, context: "")
        XCTAssertTrue(issues.contains { $0.contains("steering wheel") })
        XCTAssertTrue(issues.contains { $0.contains("anniversary") })
        let accurate = "Joseph could not make sense of the previous day. He avoided speaking to his father George for days, until the anniversary of his mother's death arrived."
        XCTAssertEqual(GroundingCheck.issues(draft: accurate, narration: notes, context: ""), [])
    }
    func testContinuationImportPreservesSourceAndCreatesNextWritingPoint() throws {
        var project = StoryProject(); let originalID = project.id
        let source = Source(name: "Chapter one.txt", text: "Joseph stood beside George. His mother had died a year earlier.")
        StoryContext.continueSource(source, in: &project)
        XCTAssertEqual(project.id, originalID)
        XCTAssertEqual(project.scenes[0].text, source.text)
        XCTAssertEqual(project.chapters.count, 2)
        XCTAssertTrue(StoryContext.continuity(project, before: project.scenes.last!.id).contains("His mother had died"))
        try project.validate()
    }
    func testContinuityDoesNotUseFutureScenesOrStylePlot() {
        var p = StoryProject()
        p.chapters[0].scenes[0].brief = "Joseph avoids George."
        var current = Scene(); current.brief = "The anniversary arrives."
        var later = Scene(); later.text = "Future revelation."
        p.chapters[0].scenes += [current, later]
        p.sources = [Source(name: "Style only", text: "Mira rides a spaceship.")]
        let context = StoryContext.continuity(p, before: current.id)
        XCTAssertTrue(context.contains("Joseph avoids George."))
        XCTAssertFalse(context.contains("Future revelation"))
        XCTAssertFalse(context.contains("spaceship"))
        let prompt = PromptBuilder.scene(project: p, scene: current, instruction: "Continue", selection: "", passages: [])
        XCTAssertFalse(prompt.contains("spaceship"))
    }
    func testWritingModesPersistAndDoNotInventResearch() throws {
        for mode in WritingMode.allCases {
            var p = StoryProject(); p.mode = mode; p.audience = "General reader"
            let decoded = try JSONDecoder().decode(StoryProject.self, from: JSONEncoder().encode(p))
            XCTAssertEqual(decoded.writingMode, mode)
            XCTAssertTrue(PromptBuilder.system(project: p).contains(mode.guidance))
        }
        XCTAssertTrue(WritingMode.technical.guidance.contains("Do not invent data"))
        XCTAssertEqual(StoryProject().writingMode, .book)
    }

    func testConservativeEditDoesNotReverseTheNarration() {
        let notes = "Joseph couldn't understand yesterday. He didn't talk to his father George for many days until his mother's death anniversary."
        XCTAssertTrue(GroundingCheck.safeCopyEdit("Joseph could not understand yesterday. He did not talk to his father George for many days, until his mother's death anniversary.", notes: notes, context: ""))
        XCTAssertFalse(GroundingCheck.safeCopyEdit("Joseph understood yesterday. He talked to his father George for many days until his mother's death anniversary.", notes: notes, context: ""))
        XCTAssertFalse(GroundingCheck.safeCopyEdit("Joseph sat in his spaceship. His mother's death anniversary arrived.", notes: notes, context: ""))
    }

    func testJosephFatherPronounHasUniqueAntecedent() {
        let notes = "The next day Joseph couldn't understand yesterday. So he doesn't talk to his father George for many days."
        var p = StoryProject()
        MemoryExtraction.explicitConnections(in: notes).apply(to: &p, sceneID: p.scenes[0].id, narration: notes)
        XCTAssertEqual(Set(p.characters.map(\.name)), Set(["Joseph", "George"]))
        XCTAssertEqual(p.relationships.first?.label, "George is Joseph’s father")
        XCTAssertTrue(MemoryExtraction.explicitConnections(in: "Joseph tells Dev about his father George.").relationships.isEmpty)
    }

    func testAnEchoOrCopyEditCannotPassAsGhostwriting() {
        let notes = "The next day Joseph couldn't understand yesterday. He did not talk to his father George for many days until his mother's death anniversary."
        XCTAssertFalse(ExpansionQuality.isDeveloped(notes, from: notes))
        XCTAssertFalse(ExpansionQuality.isDeveloped("The next day, Joseph could not understand yesterday. He did not speak to his father George for several days, until the anniversary of his mother's death.", from: notes))
        let expanded = "Joseph kept returning to the previous day, trying to understand it without knowing how he ought to feel. No answer stayed with him long enough to become a response. For days he did not speak to his father George. Silence required no choice of words and no certainty he did not yet have. Then the anniversary of his mother's death arrived, bringing another absence into the distance between them. What he had been unable to say was still there, unresolved."
        XCTAssertTrue(ExpansionQuality.isDeveloped(expanded, from: notes))
    }

    func testBeatExpansionRejectsInventedActionsAndOtherCharactersFeelings() {
        let beat = "Joseph did not talk to his father George for many days."
        let candidates = ["Joseph gripped the steering wheel, trying to understand what had happened.", "His father's silence lingered in his thoughts, leaving him unsure what to say.", "Joseph didn't know how to put his uncertainty into words, and silence asked less of him than an answer.", "Each possible response felt uncertain, as though choosing words would mean choosing what he was supposed to feel."]
        let result = BeatExpansion.select(candidates, beat: beat, context: "", preceding: "")
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.joined().contains("steering wheel"))
        XCTAssertFalse(result.joined().contains("father's silence"))
        let anchor = BeatExpansion.eventAnchor(edited: "Joseph could not understand yesterday.", beat: "The next day Joseph could not understand yesterday.", context: "")
        XCTAssertTrue(anchor.hasPrefix("The next day"))
        XCTAssertEqual(BeatExpansion.eventAnchor(edited: "Then certain days came.", beat: "Then certain days day comes that's his mother's anniversary, death anniversary.", context: ""), "Then the anniversary of his mother’s death arrived.")
    }

    func testFigurativeDetailIsNotAReplacementScene() {
        let notes = "Joseph felt uncertain about yesterday."
        let metaphor = "The feeling in his chest did not match anything he could name, like a door left ajar without a key."
        XCTAssertTrue(GroundingCheck.issues(draft: metaphor, narration: notes, context: "", requireCoverage: false).isEmpty)
        XCTAssertFalse(GroundingCheck.issues(draft: "Joseph opened the door of the house and looked at the clock.", narration: notes, context: "", requireCoverage: false).isEmpty)
    }

    func testExpansionDoesNotInventPreviousAnniversaryReaction() {
        let candidate = "Joseph felt the date coming, and when it did, it didn't move him any more than the last one did."
        XCTAssertTrue(BeatExpansion.select([candidate], beat: "Then the anniversary of his mother's death arrived.", context: "", preceding: "").isEmpty)
    }

    func testExpansionDoesNotDeclareUnspecifiedGriefAbsent() {
        let candidate = "There was no grief, not in the way Joseph thought it should be."
        XCTAssertTrue(BeatExpansion.select([candidate], beat: "Then the anniversary of his mother's death arrived.", context: "", preceding: "").isEmpty)
    }

    func testBookPDFPaginateChaptersAndExcludeUnacceptedDrafts() throws {
        var project = StoryProject(name: "The Return")
        var first = Chapter(title: "Chapter One")
        first.scenes[0].text = String(repeating: "Joseph remained unsure how to answer his father. ", count: 260) + "End of the first chapter."
        var second = Chapter(title: "Chapter Two")
        second.scenes[0].text = "The anniversary arrived. FINAL CHAPTER MARKER."
        second.scenes[0].pendingDraft = "Unaccepted alternative. DRAFT MARKER."
        project.chapters = [first, second]
        let data = try BookPDF.render(project: project)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 3)
        XCTAssertTrue(pdf.string?.contains("End of the first chapter.") == true)
        XCTAssertTrue(pdf.string?.contains("FINAL CHAPTER MARKER") == true)
        XCTAssertFalse(pdf.string?.contains("DRAFT MARKER") == true)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 432, height: 648))
        let selected = try XCTUnwrap(PDFDocument(data: BookPDF.render(project: project, chapterID: second.id, includeDrafts: true)))
        XCTAssertEqual(selected.pageCount, 2)
        XCTAssertTrue(selected.string?.contains("DRAFT MARKER") == true)
        XCTAssertFalse(selected.string?.contains("FINAL CHAPTER MARKER") == true)
        XCTAssertFalse(selected.string?.contains("Chapter One") == true)
        if let fixture = ProcessInfo.processInfo.environment["FOLIO_PDF_FIXTURE"] { try data.write(to: URL(fileURLWithPath: fixture)) }
    }

    func testAuthorLearningCoalescesTypingAndDoesNotLearnAIRevisions() throws {
        var project = StoryProject(name: "Learning")
        let sid = project.scenes[0].id
        let before = "Joseph knew exactly how he should respond to George."
        let after = "Joseph could not decide how he should respond to George."
        AuthorMemory.recordEdit(project: &project, sceneID: sid, before: before, after: after)
        AuthorMemory.recordEdit(project: &project, sceneID: sid, before: after, after: after + " He remained uncertain.")
        XCTAssertEqual(project.authorEdits?.count, 1)
        XCTAssertTrue(AuthorMemory.prompt(project: project, sceneID: sid, query: "Joseph").contains("could not decide"))
        let other = StoryProject(name: "Other")
        XCTAssertTrue(AuthorMemory.prompt(project: other, sceneID: other.scenes[0].id, query: "Joseph").isEmpty)
        let decoded = try JSONDecoder().decode(StoryProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.authorEdits, project.authorEdits)
        AuthorMemory.recordEdit(project: &project, sceneID: sid, before: after + " He remained uncertain.", after: before)
        XCTAssertTrue(project.authorEdits?.isEmpty == true)
    }
    func testAuthorEvidenceDoesNotIncludeFutureNarration() {
        var project = StoryProject()
        project.chapters[0].scenes[0].brief = "Joseph cannot understand yesterday."
        let current = project.scenes[0].id
        var future = FolioCore.Scene(); future.brief = "Joseph forgives George next year."
        project.chapters[0].scenes.append(future)
        let evidence = AuthorMemory.characterEvidence(project: project, character: StoryCharacter(name: "Joseph"), at: current).joined()
        XCTAssertTrue(evidence.contains("cannot understand"))
        XCTAssertFalse(evidence.contains("forgives"))
        XCTAssertFalse(AuthorMemory.conflicts(draft: "Joseph felt quiet certainty about a truth he had long known.", notes: "Joseph couldn't understand yesterday.").isEmpty)
    }
    func testAuthorContrastPreservesLaterParagraphCorrection() {
        let opening = String(repeating: "An unchanged opening. ", count: 50)
        let contrast = AuthorMemory.contrast(before: opening + "Joseph was certain.", after: opening + "Joseph was uncertain.")
        XCTAssertTrue(contrast.1.contains("uncertain"))
        XCTAssertLessThan(contrast.1.count, 200)
    }
    func testBookPresetsRenderWithConfiguredTypography() throws {
        var project = StoryProject(name: "Typography")
        project.chapters[0].scenes[0].text = "Joseph did not know how to respond.\n\nFor many days he did not speak to George."
        for preset in ["Classic", "Modern", "Airy"] {
            let data = try BookPDF.render(project: project, typography: BookTypography.preset(preset))
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertEqual(pdf.pageCount, 2)
            XCTAssertTrue(pdf.string?.contains("George") == true)
        }
        XCTAssertEqual(BookTypography().fontName, "Baskerville")
        XCTAssertEqual(BookTypography().paragraphSpacing, 0)
    }

}
