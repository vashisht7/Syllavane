import XCTest
import FolioCore
@testable import FolioApp

final class WorkspaceTests: XCTestCase {
    @MainActor private func fixture() throws -> (Workspace, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = Workspace(directory: dir, preferences: defaults)
        XCTAssertNil(store.error)
        store.newProject(name: "Test")
        return (store, dir, defaults)
    }
    @MainActor private func draft(_ store: Workspace, text: String = "Joseph could not understand what had happened.") {
        store.editScene { $0.brief = "Joseph could not understand what had happened."; $0.pendingDraft = text }
        store.restorePendingDraft(); store.flush()
    }
    @MainActor func testLongNarrationIsSavedAndRejectedBeforeModelCall() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        store.models.ready = true
        store.editScene { $0.brief = String(repeating: "A long idea. ", count: 600) }; store.generate()
        XCTAssertFalse(store.generating)
        XCTAssertNotNil(store.error)
        XCTAssertGreaterThan(store.scene?.brief.count ?? 0, 6000)
        store.flush(); XCTAssertGreaterThan(try store.database?.projects().first?.scenes.first?.brief.count ?? 0, 6000)
    }
    @MainActor func testNativeManualEditsPersistWithoutModelLearningItsOwnDraft() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); XCTAssertNil(store.project?.authorEdits)
        store.updateDraftFromUser("Joseph remained uncertain about how to respond to George.")
        store.flush()
        XCTAssertEqual(store.project?.authorEdits?.count, 1)
        XCTAssertEqual(try store.database?.projects().first?.scenes.first?.pendingDraft, store.proposal?.text)
    }
    @MainActor func testSelectedRevisionPreservesOutsideText() async throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        let original = "First paragraph stays.\n\nJoseph was unsure.\n\nLast paragraph stays."
        draft(store, text: original)
        store.draftSelectedText = "Joseph was unsure."
        store.draftSelection = (original as NSString).range(of: store.draftSelectedText)
        store.models.ready = true
        store.models.completionTransport = { system, _ in system.contains("Check a revision") ? "{\"faithful\":true}" : "Joseph remained uncertain." }
        store.reviseDraft(instruction: "Keep the uncertainty")
        for _ in 0..<100 where store.generating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.proposal?.text, "First paragraph stays.\n\nJoseph remained uncertain.\n\nLast paragraph stays.")
        store.undoAIRevision(); XCTAssertEqual(store.proposal?.text, original)
    }
    @MainActor func testUnsubmittedFeedbackIsSavedAndSurvivesOfflineAttempt() throws {
        let (store, dir, defaults) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store)
        store.feedback = "Keep the uncertainty and tone down the imagery."
        store.applyFeedback()
        XCTAssertEqual(store.feedback, "Keep the uncertainty and tone down the imagery.")
        XCTAssertTrue(store.showSettings)
        store.flush()
        let reopened = Workspace(directory: dir, preferences: defaults); defer { reopened.shutdown() }
        XCTAssertEqual(reopened.feedback, store.feedback)
        XCTAssertNil(reopened.recoveredNarration)
    }
    @MainActor func testCorruptLibraryFailsClosedAndPreservesItsFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.sqlite")
        let bytes = Data("This is not a SQLite library".utf8); try bytes.write(to: file)
        let store = Workspace(directory: dir, preferences: UserDefaults(suiteName: UUID().uuidString)!); defer { store.shutdown() }
        XCTAssertNotNil(store.error); XCTAssertNil(store.database)
        store.newProject(name: "Must not overwrite")
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testLibraryBackupRecoveryCreatesCopiesWithoutOverwritingCurrentBook() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); let first = try XCTUnwrap(store.project)
        let backup = dir.appendingPathComponent("fixture-backup.sqlite")
        try store.database?.backup(to: backup)
        store.updateDraftFromUser("A newer version must remain available."); store.flush()
        store.recoverLibrary(from: backup)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertEqual(store.projects.first(where: { $0.id == first.id })?.scenes.first?.pendingDraft, "A newer version must remain available.")
        XCTAssertEqual(store.project?.scenes.first?.pendingDraft, first.scenes.first?.pendingDraft)
        XCTAssertNotEqual(store.projectID, first.id)
        XCTAssertTrue(store.project?.name.hasSuffix("(recovered)") == true)
    }
    @MainActor func testContinuationSurvivesRelaunchAndProjectSwitch() throws {
        let (store, dir, defaults) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store)
        let originalID = store.projectID
        store.continuationText = "Next, George remains silent."
        store.flush()
        store.newProject(name: "Other")
        store.selectProject(originalID!)
        XCTAssertEqual(store.continuationText, "Next, George remains silent.")
        let reopened = Workspace(directory: dir, preferences: defaults); defer { reopened.shutdown() }
        XCTAssertEqual(reopened.continuationText, "Next, George remains silent.")
        XCTAssertEqual(reopened.proposal?.text, store.proposal?.text)
    }
    @MainActor func testContinuingPreservesPendingDraftAndUsesNewMoment() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); let original = store.sceneID!
        let pending = store.proposal?.text
        store.continuationText = "George asks about tomorrow."
        store.submitNarration() // No model started; notes still saved for later generation.
        XCTAssertNotEqual(store.sceneID, original)
        XCTAssertEqual(store.scene?.brief, "George asks about tomorrow.")
        XCTAssertEqual(store.project?.scenes.first(where: { $0.id == original })?.pendingDraft, pending)
        XCTAssertNil(store.project?.scenes.first(where: { $0.id == original })?.continuation)
        XCTAssertTrue(store.showSettings)
    }
    @MainActor func testFailedSavePreventsNavigationAndRetainsLatestText() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        let oldID = store.projectID
        store.newProject(name: "Other"); let otherID = store.projectID
        store.selectProject(oldID!)
        store.edit { $0.schemaVersion = 99 }
        store.selectProject(otherID!)
        XCTAssertEqual(store.projectID, oldID)
        XCTAssertFalse(store.saved)
        XCTAssertNotNil(store.error)
        store.edit { $0.schemaVersion = 1 }; XCTAssertTrue(store.flush())
    }
    @MainActor func testAcceptConflictCannotOverwriteManualWriting() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); store.editScene { $0.text = "A newer manual version." }
        store.acceptDraft()
        XCTAssertEqual(store.scene?.text, "A newer manual version.")
        XCTAssertNotNil(store.proposal)
        XCTAssertNotNil(store.error)
    }
    @MainActor func testRetryReplacesSpeechInsteadOfDuplicatingIt() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        store.editScene { $0.brief = "The earlier notes. Old speech." }
        store.replaceRetriedDictation("Corrected speech.", base: "The earlier notes.")
        XCTAssertEqual(store.scene?.brief, "The earlier notes. Corrected speech.")
        store.replaceRetriedDictation("Corrected speech.", base: "The earlier notes.")
        XCTAssertEqual(store.scene?.brief, "The earlier notes. Corrected speech.")
        store.replaceRetriedDictation("", base: "The earlier notes.")
        XCTAssertEqual(store.scene?.brief, "The earlier notes. Corrected speech.")
    }
    @MainActor func testUndoCannotEraseSubsequentManualChanges() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); store.revisionBefore = "Before"; store.revisionAfter = store.proposal?.text
        store.updateDraftFromUser("The author made a later correction here.")
        store.undoAIRevision()
        XCTAssertEqual(store.proposal?.text, "The author made a later correction here.")
    }
    @MainActor func testGenerationFailureKeepsNarrationAndNoPartialDraft() async throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        store.models.ready = true
        store.models.completionTransport = { _, _ in throw FolioError.message("Connection interrupted") }
        store.editScene { $0.brief = "Joseph remains silent." }
        store.generate()
        for _ in 0..<100 where store.generating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.generating)
        XCTAssertEqual(store.scene?.brief, "Joseph remains silent.")
        XCTAssertNil(store.proposal)
        XCTAssertNil(store.scene?.pendingDraft)
        XCTAssertNotNil(store.error)
    }
    @MainActor func testCancelThenNewProjectDiscardsLateResponse() async throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        store.models.ready = true
        store.models.completionTransport = { _, _ in
            try? await Task.sleep(for: .milliseconds(100)) // Simulate a server ignoring cancellation.
            return "Joseph remains silent."
        }
        store.editScene { $0.brief = "Joseph remains silent." }; let originalID = store.projectID; store.generate()
        try await Task.sleep(for: .milliseconds(20))
        store.newProject(name: "Separate book")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.project?.name, "Separate book")
        XCTAssertNil(store.projects.first(where: { $0.id == originalID })?.scenes.first?.pendingDraft)
        XCTAssertNil(store.proposal)
        XCTAssertEqual(store.scene?.brief, "")
        XCTAssertFalse(store.generating)
    }
    @MainActor func testFinishedChapterCannotContainUnreviewedEarlierDraft() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); store.newScene()
        store.editScene { $0.text = "Some accepted writing." }
        store.finishChapter()
        XCTAssertNotEqual(store.chapter?.finished, true)
        XCTAssertTrue(store.toast?.contains("earlier drafts") == true)
    }
    @MainActor func testInvalidSceneIDDoesNotDestroyCurrentDraft() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); let original = store.sceneID
        store.selectScene(UUID())
        XCTAssertEqual(store.sceneID, original)
        XCTAssertNotNil(store.proposal)
    }
    @MainActor func testFailedRebuildPreservesExistingDraftAndSavedRevision() async throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        let original = "Joseph waited without knowing what he should say to George."
        draft(store, text: original)
        store.models.ready = true
        store.models.completionTransport = { _, _ in throw FolioError.message("Writer interrupted") }
        store.regenerateDraft()
        for _ in 0..<100 where store.generating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.proposal?.text, original)
        XCTAssertEqual(store.scene?.pendingDraft, original)
        XCTAssertEqual(try store.database?.projects().first?.scenes.first?.pendingDraft, original)
    }
    @MainActor func testOfflineAndFailedSaveRebuildCannotRemoveDraft() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); let original = store.proposal?.text
        store.regenerateDraft()
        XCTAssertEqual(store.proposal?.text, original)
        XCTAssertTrue(store.showSettings)
        store.models.ready = true; store.edit { $0.schemaVersion = 99 }
        store.regenerateDraft()
        XCTAssertFalse(store.generating)
        XCTAssertEqual(store.proposal?.text, original)
        store.edit { $0.schemaVersion = 1 }; store.flush()
    }
    @MainActor func testKeptRewriteLearnsOnlyAfterApprovalAndSurvivesReopen() async throws {
        let (store, dir, defaults) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        let original = "Joseph did not know how he should respond to George."
        let replacement = "Joseph remained uncertain about how to respond to George."
        draft(store, text: original); store.models.ready = true
        store.models.completionTransport = { system, _ in system.contains("Check a revision") ? "{\"faithful\":true}" : replacement }
        store.reviseDraft(instruction: "Tone down")
        for _ in 0..<100 where store.generating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.proposal?.text, replacement)
        XCTAssertTrue(store.project?.approvedRewrites?.isEmpty != false)
        XCTAssertTrue(store.project?.authorDirections?.isEmpty != false)
        let reopened = Workspace(directory: dir, preferences: defaults); defer { reopened.shutdown() }
        XCTAssertEqual(reopened.revisionBefore, original)
        XCTAssertEqual(reopened.revisionAfter, replacement)
        XCTAssertTrue(reopened.keepAIRevision())
        XCTAssertEqual(reopened.project?.approvedRewrites?.count, 1)
        XCTAssertNil(reopened.project?.authorEdits)
        XCTAssertNil(reopened.scene?.pendingRevision)
        let prompt = AuthorMemory.prompt(project: reopened.project!, sceneID: reopened.sceneID!, query: "Joseph")
        XCTAssertTrue(prompt.contains("APPROVED REWRITE"))
        XCTAssertEqual(AuthorMemory.characterEvidence(project: reopened.project!, character: StoryCharacter(name: "Joseph"), at: reopened.sceneID!).count, 1)
        reopened.keepAIRevision(); XCTAssertEqual(reopened.project?.approvedRewrites?.count, 1)
    }
    @MainActor func testUndoAfterReopenDoesNotLearnRejectedRewrite() throws {
        let (store, dir, defaults) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        let before = "Joseph did not know how he should respond to George."
        let after = "Joseph remained uncertain about how to respond to George."
        draft(store, text: after)
        store.editScene { $0.pendingRevision = PendingRevision(before: before, after: after, instruction: "Tone down") }; store.flush()
        let reopened = Workspace(directory: dir, preferences: defaults); defer { reopened.shutdown() }
        reopened.undoAIRevision()
        XCTAssertEqual(reopened.proposal?.text, before)
        XCTAssertNil(reopened.scene?.pendingRevision)
        XCTAssertTrue(reopened.project?.approvedRewrites?.isEmpty != false)
        XCTAssertEqual(try reopened.database?.projects().first?.scenes.first?.pendingDraft, before)
    }
    @MainActor func testCancelledRebuildKeepsPreviousDraft() async throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); let original = store.proposal?.text
        store.models.ready = true
        store.models.completionTransport = { _, _ in try? await Task.sleep(for: .milliseconds(100)); return "Late response" }
        store.regenerateDraft(); try await Task.sleep(for: .milliseconds(20)); store.cancelGeneration()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.proposal?.text, original)
        XCTAssertEqual(store.scene?.pendingDraft, original)
    }
    @MainActor func testSaveFailurePreventsDiscardAndChapterCreation() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store); let original = store.proposal?.text; let chapterCount = store.project?.chapters.count
        store.edit { $0.schemaVersion = 99 }
        store.discardDraft(); store.newChapter()
        XCTAssertEqual(store.proposal?.text, original)
        XCTAssertEqual(store.scene?.pendingDraft, original)
        XCTAssertEqual(store.project?.chapters.count, chapterCount)
        store.edit { $0.schemaVersion = 1 }; store.flush()
    }
    @MainActor func testApprovedExamplesDoNotLeakBackwardInStoryTime() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        let earlier = store.sceneID!; store.newScene(); let later = store.sceneID!
        store.edit { $0.approvedRewrites = [ApprovedRewrite(sceneID: later, before: "He was uncertain.", after: "A later secret should stay in its own scene.", instruction: "Explain more")] }
        let project = store.project!
        XCTAssertFalse(AuthorMemory.prompt(project: project, sceneID: earlier, query: "secret").contains("later secret"))
        XCTAssertTrue(AuthorMemory.prompt(project: project, sceneID: later, query: "secret").contains("later secret"))
        let encoded = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(StoryProject.self, from: encoded).approvedRewrites, project.approvedRewrites)
    }
    @MainActor func testSavedPsychologicalDriftIsFlaggedForRebuild() throws {
        let (store, dir, _) = try fixture(); defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        draft(store, text: "Joseph felt quiet certainty about a truth he had long known. He knew exactly how to respond now, and finally understood.")
        XCTAssertTrue(store.draftNeedsReview)
        store.discardDraft(); XCTAssertFalse(store.draftNeedsReview)
    }
}
