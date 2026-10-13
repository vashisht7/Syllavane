import SwiftUI
import AppKit

@main
struct FolioApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var workspace = Workspace()
    var body: some Scene {
        Window("Syllavane", id: "main") {
            WorkspaceView(store: workspace)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear { delegate.workspace = workspace; workspace.launch() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("All Projects") { workspace.showLibrary() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("New Project…") { workspace.showNewProject = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Continue Narration") { if let id = workspace.project?.scenes.last?.id { workspace.libraryVisible = false; workspace.selectScene(id) } }.keyboardShortcut("n")
                Button("Finish Chapter Here") { workspace.finishChapter() }.keyboardShortcut("n", modifiers: [.command, .option])
                Divider()
                Button("Import Project…") { workspace.importProject() }
                Button("Import Writing Samples…") { workspace.importSources() }.keyboardShortcut("i")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { workspace.flush(reason: "Manual save") }.keyboardShortcut("s")
                Button("Export Manuscript…") { workspace.exportProject(manuscript: true) }.keyboardShortcut("e")
                Button("Export Project Backup…") { workspace.exportProject(manuscript: false) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { workspace.showSettings = true }.keyboardShortcut(",")
            }
            CommandMenu("Writing") {
                Button("Create Draft from Narration") { workspace.submitNarration() }.keyboardShortcut(.return, modifiers: .command)
                Button("Start / Stop Dictation") { workspace.toggleDictation() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Characters…") { workspace.showCharacters = true }.keyboardShortcut("k")
                Button("Story Map") { workspace.tab = .map }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Revision History…") { workspace.loadHistory() }
            }
            CommandGroup(after: .textEditing) {
                Button("Search All Writing…") { workspace.showSearch = true }.keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Focus on Writing") { workspace.focusMode.toggle(); workspace.tab = .manuscript }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Preview and Save PDF…") { workspace.persistDraft(); workspace.flush(); workspace.showBookPreview = true }.keyboardShortcut("p")
                Button("What I’ve Learned…") { workspace.showStyle = true }

                Button("Toggle Projects Sidebar") { workspace.sidebarVisible.toggle() }.keyboardShortcut("s", modifiers: [.command, .option])
                Button("Toggle Story Details") { workspace.inspector.toggle() }.keyboardShortcut("\\", modifiers: [.command, .option])
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: Workspace?
    private var sleepObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.workspace?.pauseForSleep() }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows { window.backgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1); window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = true }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.prepareForQuit()
        if workspace?.saved == false {
            let alert = NSAlert(); alert.messageText = "Your latest changes could not be saved."
            alert.informativeText = "Keep Syllavane open and export a project backup to preserve your writing."
            alert.addButton(withTitle: "Keep Open"); alert.addButton(withTitle: "Quit Anyway")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { workspace?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
