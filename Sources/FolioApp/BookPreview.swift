import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import FolioCore

struct BookPreview: View {
    @ObservedObject var store: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var chapterID: UUID? = nil
    @State private var includeDrafts = true
    @State private var data = Data()
    @State private var message = ""
    @State private var rendering = false
    @State private var renderTask: Task<Void, Never>?
    @State private var renderID = UUID()
    @State private var typography = BookTypography()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.project?.writingMode == .book ? "Book preview" : "Document preview").font(.system(size: 17, weight: .medium))
                Spacer()
                Picker("Chapters", selection: $chapterID) {
                    Text(store.project?.writingMode == .book ? "All chapters" : "All documents").tag(Optional<UUID>.none)
                    ForEach(store.project?.chapters ?? []) { Text($0.title).tag(Optional($0.id)) }
                }.labelsHidden().frame(width: 190)
                Button("Save PDF…") { save() }.buttonStyle(QuietButton(prominent: true)).disabled(data.isEmpty || rendering)
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(QuietButton()).help("Close book preview")
            }.padding(18)
            HStack {
                Toggle("Include unaccepted drafts", isOn: $includeDrafts).toggleStyle(.checkbox)
                Spacer()
                Text(rendering ? "Updating preview…" : message.isEmpty ? (store.project?.writingMode == .book ? "6 × 9 in · chapter openings · page numbers" : "A4 · document layout · page numbers") : message).foregroundStyle(Palette.secondary)
            }.font(.system(size: 11)).padding(.horizontal, 18).padding(.bottom, 14)
            HStack(spacing: 16) {
                Picker("Theme", selection: Binding(get: { typography.themeName }, set: { typography = BookTypography.preset($0) })) { ForEach(["Classic", "Modern", "Airy"], id: \.self) { Text($0) } }.frame(width: 170)
                Picker("Font", selection: $typography.fontName) { ForEach(["Baskerville", "Georgia", "Palatino", "Times New Roman"], id: \.self) { Text($0) } }.frame(width: 200)
                Stepper("Size \(Int(typography.fontSize))", value: $typography.fontSize, in: 10...16, step: 1)
                Stepper("Paragraph gap \(Int(typography.paragraphSpacing))", value: $typography.paragraphSpacing, in: 0...14, step: 2)
            }.font(.system(size: 11)).padding(.horizontal, 18).padding(.bottom, 14)
            DisclosureGroup("Page and line spacing") {
                HStack {
                    Stepper("Line gap \(Int(typography.lineSpacing))", value: $typography.lineSpacing, in: 1...8, step: 1)
                    Stepper("Margins \(Int(typography.margin)) pt", value: $typography.margin, in: 36...66, step: 3)
                    Stepper("Indent \(Int(typography.indent)) pt", value: $typography.indent, in: 0...24, step: 2)
                }.padding(.top, 8)
            }.font(.system(size: 11)).padding(.horizontal, 18).padding(.bottom, 12)
            PDFCanvas(data: data).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 850, height: min(720, max(480, (NSScreen.main?.visibleFrame.height ?? 900) - 120))).background(Palette.background).foregroundStyle(Palette.text)
        .onChange(of: typography) { _, value in store.edit { $0.bookTypography = value }; refresh() }
        .onDisappear { renderTask?.cancel() }
        .onAppear { typography = store.project?.bookTypography ?? BookTypography.preset(store.project?.writingMode == .book ? "Classic" : "Modern"); refresh() }.onChange(of: chapterID) { _, _ in refresh() }.onChange(of: includeDrafts) { _, _ in refresh() }
    }
    private func refresh() {
        guard let project = store.project else { return }
        renderTask?.cancel()
        let id = UUID(); renderID = id; rendering = true
        let chapter = chapterID, drafts = includeDrafts, style = typography
        renderTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let job = Task.detached(priority: .userInitiated) { try BookPDF.render(project: project, chapterID: chapter, includeDrafts: drafts, typography: style) }
                let pdf = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                guard !Task.isCancelled, renderID == id else { return }
                data = pdf; message = ""; rendering = false
            } catch is CancellationError { }
            catch { guard renderID == id else { return }; message = "Could not prepare the PDF: " + error.localizedDescription; data = Data(); rendering = false }
        }
    }
    private func save() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = (store.project?.name ?? "Book") + (chapterID.flatMap { id in store.project?.chapters.first { $0.id == id }?.title }.map { " — " + $0 } ?? "") + ".pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); message = "PDF saved" } catch { message = error.localizedDescription }
        }
    }
}
private struct PDFCanvas: NSViewRepresentable {
    var data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1); return view
    }
    func updateNSView(_ view: PDFView, context: Context) { if context.coordinator.data != data { context.coordinator.data = data; view.document = PDFDocument(data: data) } }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var data = Data() }
}
