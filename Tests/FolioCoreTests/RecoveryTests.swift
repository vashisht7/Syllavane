import XCTest
import CSQLite
@testable import FolioCore

final class RecoveryTests: XCTestCase {
    func testViewpointGuardKeepsTheAuthorCharacter() {
        let notes = "Mira sees her father Dev after ten years. She is angry but hides it."
        XCTAssertEqual(BeatExpansion.viewpointSubject(notes: notes), "Mira")
        XCTAssertTrue(BeatExpansion.viewpointDirection(notes: notes, style: "").contains("solely inside Mira"))
        XCTAssertEqual(BeatExpansion.viewpointSubject(notes: "She sees George."), "She")
        let candidates = ["Dev felt that the silence was filled with his own grief.", "He felt that the silence was filled with his own grief.", "Mira remembers the quiet tension she had seen in him before.", "Mira felt anger beneath the silence, still uncertain how to respond."]
        let accepted = BeatExpansion.select(candidates, beat: notes, context: notes, preceding: "", viewpointNotes: notes)
        XCTAssertFalse(accepted.contains(where: { $0.hasPrefix("Dev") || $0.hasPrefix("He") || $0.contains("remembers") }))
    }
    func testFirstPersonAuthorChoiceIsHonored() {
        XCTAssertTrue(BeatExpansion.viewpointDirection(notes: "Mira waits.", style: "First-person narration").contains("first-person"))
        let candidates = ["I felt the uncertainty in my thoughts and could not find an answer."]
        XCTAssertFalse(BeatExpansion.select(candidates, beat: "Mira felt uncertain.", context: "Mira felt uncertain.", preceding: "", allowFirstPerson: true).isEmpty)
    }
    func testDuplicateLibraryIdentifiersFailClosed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("library.sqlite")
        let db = try ProjectDatabase(url: url)
        var p = StoryProject(); p.id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!; try db.save(p)
        var handle: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK); defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "INSERT INTO projects SELECT lower(id),document,updated FROM projects", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try db.projects())
    }
    func testConfusionCannotBecomeMemoryLossOrDoubtAboutReality() {
        let notes = "Joseph couldn't understand yesterday or how to react."
        XCTAssertFalse(AuthorMemory.conflicts(draft: "He could not tell if the event had happened.", notes: notes).isEmpty)
        XCTAssertFalse(AuthorMemory.conflicts(draft: "Joseph did not know if he had woken up or stopped breathing.", notes: notes).isEmpty)
        XCTAssertTrue(AuthorMemory.conflicts(draft: "He could not decide how to react.", notes: notes).isEmpty)
        XCTAssertTrue(AuthorMemory.conflicts(draft: "He wondered if the event had happened.", notes: "He suffers amnesia and doubts if the event had happened.").isEmpty)
    }
    func testEventAnchorDoesNotRepeatPreviousBeats() {
        let beat = "He did not speak to his father George for many days."
        let edit = "Joseph could not understand what had happened yesterday and did not know how to react to it, and he did not speak to his father George for many days."
        XCTAssertEqual(BeatExpansion.eventAnchor(edited: edit, beat: beat, context: edit), beat)
    }
    func testAudioCheckpointsKeepRecordingAndDestinationTogether() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let recovery = VoiceRecoveryStore(directory: dir)
        let pid = UUID(), sid = UUID()
        recovery.checkpoint(VoiceRecoverySnapshot(projectID: pid, sceneID: sid, revision: false, transcript: "First", wav: Data([1, 2])))
        recovery.checkpoint(VoiceRecoverySnapshot(projectID: pid, sceneID: sid, revision: true, transcript: "Latest", wav: Data([3, 4, 5])))
        let reopened = VoiceRecoveryStore(directory: dir)
        recovery.drain()
        let result = try XCTUnwrap(reopened.read())
        XCTAssertEqual(result.projectID, pid); XCTAssertEqual(result.sceneID, sid)
        XCTAssertEqual(result.transcript, "Latest"); XCTAssertEqual(result.wav, Data([3, 4, 5])); XCTAssertTrue(result.revision)
        recovery.clear(); XCTAssertNil(reopened.read())
    }
    func testMalformedRecoveryIsNotApplied() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("invalid recovery".utf8).write(to: dir.appendingPathComponent("interrupted-voice.plist"))
        XCTAssertNil(VoiceRecoveryStore(directory: dir).read())
    }
    func testInvalidPDFSettingsFailWithoutRendering() {
        var typography = BookTypography(); typography.margin = 10000
        XCTAssertThrowsError(try BookPDF.render(project: StoryProject(), typography: typography))
        typography = BookTypography(); typography.fontSize = .nan
        XCTAssertThrowsError(try BookPDF.render(project: StoryProject(), typography: typography))
        XCTAssertThrowsError(try BookPDF.render(project: StoryProject(), chapterID: UUID()))
    }
    func testInvalidRelationshipSceneIsRejectedOnImport() {
        var p = StoryProject(); let a = StoryCharacter(name: "A"), b = StoryCharacter(name: "B")
        p.characters = [a, b]; var edge = Relationship(from: a.id, to: b.id, label: "friend")
        edge.sourceSceneID = UUID(); p.relationships = [edge]
        XCTAssertThrowsError(try p.validate())
    }
    func testDatabaseRollbackKeepsEarlierProjectAndHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ProjectDatabase(url: dir.appendingPathComponent("test.sqlite"))
        var p = StoryProject(name: "Preserved"); try db.save(p, reason: "Original")
        p.schemaVersion = 50; XCTAssertThrowsError(try db.save(p, reason: "Invalid"))
        XCTAssertEqual(try db.projects().first?.name, "Preserved")
        XCTAssertEqual(try db.revisions(projectID: p.id).count, 1)
        XCTAssertNil(try db.embedding(key: "missing"))
    }
}
