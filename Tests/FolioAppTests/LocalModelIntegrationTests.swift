import XCTest
import FolioCore
@testable import FolioApp

final class LocalModelIntegrationTests: XCTestCase {
    @MainActor func testActualWriterAcrossWritingModes() async throws {
        guard ProcessInfo.processInfo.environment["FOLIO_RUN_MODEL_TESTS"] == "1" else { throw XCTSkip("Opt in to local model integration tests with FOLIO_RUN_MODEL_TESTS=1.") }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("syllavane-integration-" + UUID().uuidString)
        let models = LocalEngines(modelDirectory: AppPaths.models, resourceDirectory: root.appendingPathComponent("dist/Syllavane.app/Contents/Resources"), runtimeDirectory: dir)
        let store = Workspace(directory: dir, preferences: UserDefaults(suiteName: UUID().uuidString)!, engines: models)
        defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        await models.prepare(); XCTAssertTrue(models.ready, models.error ?? models.status)
        guard models.ready else { return }
        let cases: [(String, WritingMode, String)] = [
            ("Joseph", .book, "The next day Joseph couldn't understand what happened yesterday and how he should react to it. He doesn't talk to his father George for many days, until his mother's death anniversary."),
            ("Restraint", .book, "Mira sees her father Dev after ten years. She feels angry but hides it. They sit down for tea. Neither speaks yet."),
            ("Blog", .blog, "Explain why I keep a daily writing habit. I write for twenty minutes before work, and it helps me notice my own thoughts. Don't claim research or statistics."),
            ("Post", .social, "I finished my first chapter today. It took longer than I expected, but I'm happy I kept going."),
            ("Paper", .technical, "Describe an experiment comparing two sorting algorithms on the same dataset. Results have not been measured yet. State that timing and memory measurements are still needed.")
        ]
        var records: [[String: Any]] = []
        let filter = ProcessInfo.processInfo.environment["FOLIO_TEST_CASE"]
        for (name, mode, notes) in cases where filter == nil || name == filter {
            var attempts: [[String: Any]] = []
            store.evaluationObserver = { stage, text, issues in attempts.append(["stage": stage, "text": text, "issues": issues]) }
            store.newProject(name: "QA " + name, mode: mode)
            store.edit { $0.style = "Clear, restrained writing. Stay close to the narrator's supplied feelings. Avoid decorative imagery, invented memories, or new actions." }
            store.editScene { $0.brief = notes }; store.generate()
            let start = Date()
            while store.generating && Date().timeIntervalSince(start) < 180 { try await Task.sleep(for: .milliseconds(100)) }
            let draft = store.proposal?.text ?? ""
            records.append(["case": name, "mode": mode.rawValue, "notes": notes, "draft": draft, "notice": store.draftNotice, "error": store.error ?? "", "seconds": Date().timeIntervalSince(start), "attempts": attempts])
            XCTAssertFalse(store.generating, "Timeout: " + name)
            XCTAssertFalse(draft.isEmpty, name + ": " + store.draftNotice + (store.error ?? ""))
            if name == "Joseph" { XCTAssertTrue(draft.lowercased().contains("anniversary")); XCTAssertTrue(draft.contains("George")); XCTAssertTrue(AuthorMemory.conflicts(draft: draft, notes: notes).isEmpty); XCTAssertFalse(draft.lowercased().contains("memory was real")) }
            if name == "Restraint" {
                for claim in ["Dev noticed", "Dev waited", "He noticed", "He waited", "always did"] { XCTAssertFalse(draft.contains(claim), "Entered the father's unprovided experience: " + claim) }
            }
            if mode == .social { XCTAssertLessThanOrEqual(draft.count, 280) }
            if mode == .technical { XCTAssertFalse(draft.contains("p <")); XCTAssertFalse(draft.contains("2024)")) }
            store.cancelGeneration(); store.error = nil
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("dist/local-model-evaluation.json"), options: .atomic)
    }
    @MainActor func testActualWriterApprovedRevisionMemory() async throws {
        guard ProcessInfo.processInfo.environment["FOLIO_RUN_MODEL_TESTS"] == "1" else { throw XCTSkip("Opt in to installed writer tests.") }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("syllavane-revision-" + UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let models = LocalEngines(modelDirectory: AppPaths.models, resourceDirectory: root.appendingPathComponent("dist/Syllavane.app/Contents/Resources"), runtimeDirectory: dir)
        let store = Workspace(directory: dir, preferences: defaults, engines: models)
        defer { store.shutdown(); try? FileManager.default.removeItem(at: dir) }
        await models.prepare(); XCTAssertTrue(models.ready, models.error ?? models.status)
        guard models.ready else { return }
        store.newProject(name: "QA approved rewrite")
        let original = "Joseph could not understand what had happened yesterday. He did not know how to respond to George, his father. The uncertainty stayed with him, and he could not find words for it."
        store.edit { $0.style = "Plain, restrained close third person. Preserve uncertainty. Avoid decorative imagery." }
        store.editScene { $0.brief = "Joseph could not understand what happened yesterday or how to respond to his father George."; $0.pendingDraft = original }
        store.restorePendingDraft()
        let start = Date(); store.reviseDraft(instruction: "Use fewer words and less description. Preserve Joseph's uncertainty and his relationship to George.")
        while store.generating && Date().timeIntervalSince(start) < 90 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(store.generating)
        let after = store.proposal?.text ?? ""
        XCTAssertNotEqual(after, original, store.draftNotice + (store.error ?? ""))
        XCTAssertTrue(AuthorMemory.conflicts(draft: after, notes: store.scene!.brief).isEmpty)
        XCTAssertTrue(store.keepAIRevision())
        XCTAssertEqual(store.project?.approvedRewrites?.count, 1)
        let reopened = Workspace(directory: dir, preferences: defaults)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.project?.approvedRewrites?.first?.after, after)
        let record: [String: Any] = ["before": original, "after": after, "seconds": Date().timeIntervalSince(start), "approvedExamples": reopened.project?.approvedRewrites?.count ?? 0]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("dist/approved-rewrite-evaluation.json"))
    }
}
