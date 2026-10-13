import SwiftUI
import AppKit
import FolioCore

enum Palette {
    static let background = Color(white: 0.066)
    static let sidebar = Color(white: 0.052)
    static let panel = Color(white: 0.085)
    static let tile = Color(white: 0.11)
    static let hover = Color(white: 0.145)
    static let line = Color(white: 0.17)
    static let text = Color(white: 0.89)
    static let secondary = Color(white: 0.56)
    static let muted = Color(white: 0.55)
}
struct QuietButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(prominent ? Palette.background : Palette.text)
            .background(prominent ? Color(white: configuration.isPressed ? 0.7 : 0.88) : Color(white: configuration.isPressed ? 0.18 : 0.115))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(prominent ? .clear : Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 14)).foregroundStyle(hovered ? Palette.text : Palette.secondary).frame(width: 30, height: 30).background(hovered ? Palette.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 6)) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help).onHover { hovered = $0 }
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.secondary) }
}
struct Avatar: View {
    var data: Data?
    var name: String = ""
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill() }
            else { Text(name.isEmpty ? "F" : String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .medium, design: .serif)).foregroundStyle(Palette.text).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.18)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }
}
struct PanelField: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    var lines = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Eyebrow(text: title)
            TextField(placeholder, text: $value, axis: .vertical).lineLimit(lines...max(lines, 12)).textFieldStyle(.plain).font(.system(size: 13)).lineSpacing(4).padding(12).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
        }
    }
}
struct EmptyHint: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Palette.secondary)
            Text(title).font(.system(size: 23, weight: .regular, design: .serif)).foregroundStyle(Palette.text)
            Text(detail).font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ManuscriptEditor: NSViewRepresentable {
    @Binding var text: String
    var onSelection: (String, NSRange) -> Void
    var onRewrite: ((String, Bool) -> Void)? = nil
    var canRewrite = true
    var changeID: UUID? = nil
    var changedRange: NSRange? = nil
    var growWithText = false
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = !growWithText; scroll.drawsBackground = false
        let view = NSTextView(); view.delegate = context.coordinator
        view.isRichText = false; view.allowsUndo = true; view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = true; view.drawsBackground = false
        view.textColor = NSColor(calibratedWhite: 0.84, alpha: 1)
        view.insertionPointColor = .white
        view.font = NSFont(name: "Georgia", size: 17) ?? NSFont.systemFont(ofSize: 18)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 4
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: view.font!, .foregroundColor: view.textColor!, .paragraphStyle: paragraph]
        view.textContainerInset = NSSize(width: 4, height: 12)
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Manuscript editor")
        scroll.documentView = view; view.string = text
        return scroll
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard growWithText, let width = proposal.width, width > 0,
              let view = scroll.documentView as? NSTextView,
              let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(1, width - view.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(100, ceil(layout.usedRect(for: container).height) + view.textContainerInset.height * 2))
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = canRewrite
        if view.string != text { view.string = text; view.setSelectedRange(NSRange(location: 0, length: 0)) }
        if let id = changeID, id != context.coordinator.lastPulse, let range = changedRange, NSMaxRange(range) <= (view.string as NSString).length {
            context.coordinator.lastPulse = id
            view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.70, green: 0.72, blue: 0.77, alpha: 0.36), forCharacterRange: range)
            view.scrollRangeToVisible(range)
            var glow: ChangeGlow?
            if let layout = view.layoutManager, let container = view.textContainer {
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let box = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: view.textContainerInset.width, dy: view.textContainerInset.height).insetBy(dx: -3, dy: -3)
                let overlay = ChangeGlow(frame: box); overlay.wantsLayer = true
                let shape = CAShapeLayer(); shape.frame = overlay.bounds; shape.path = CGPath(roundedRect: overlay.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
                shape.fillColor = NSColor.clear.cgColor; shape.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor; shape.lineWidth = 1
                shape.shadowColor = NSColor.white.cgColor; shape.shadowOpacity = 0.45; shape.shadowRadius = 6; shape.shadowOffset = .zero
                overlay.layer?.addSublayer(shape); view.addSubview(overlay); glow = overlay
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 2.4; shape.opacity = 0; shape.add(fade, forKey: "change")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak view, weak glow] in
                glow?.removeFromSuperview()
                guard let view else { return }
                view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (view.string as NSString).length))
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ManuscriptEditor
        var lastPulse: UUID?
        var popover: NSPopover?
        var pending: DispatchWorkItem?
        init(_ parent: ManuscriptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { guard let view = notification.object as? NSTextView else { return }; parent.text = view.string }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange()
            let value = NSMaxRange(range) <= (view.string as NSString).length ? (view.string as NSString).substring(with: range) : ""
            parent.onSelection(value, range)
            pending?.cancel()
            if range.length == 0 || !parent.canRewrite { popover?.close(); return }
            guard parent.onRewrite != nil else { return }
            let work = DispatchWorkItem { [weak self, weak view] in
                guard let self, let view, view.selectedRange() == range, self.parent.canRewrite else { return }
                self.showTools(view: view, range: range, value: value)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        func showTools(view: NSTextView, range: NSRange, value: String) {
            guard NSEvent.pressedMouseButtons == 0 else {
                let work = DispatchWorkItem { [weak self, weak view] in
                    guard let self, let view, view.selectedRange() == range else { return }
                    self.showTools(view: view, range: range, value: value)
                }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
                return
            }
            popover?.close()
            let tools = NSPopover(); tools.behavior = .transient; tools.animates = true
            tools.contentViewController = NSHostingController(rootView: PassageTools { [weak self, weak view, weak tools] instruction, remember in
                guard let self, let view,
                      NSMaxRange(range) <= (view.string as NSString).length,
                      (view.string as NSString).substring(with: range) == value else { tools?.close(); return }
                tools?.close()
                self.parent.onSelection(value, range)
                self.parent.onRewrite?(instruction, remember)
            })
            tools.contentSize = NSSize(width: 300, height: 142)
            popover = tools
            let screenRect = view.firstRect(forCharacterRange: NSRange(location: range.location, length: 1), actualRange: nil)
            guard let window = view.window else { return }
            let local = view.convert(window.convertFromScreen(screenRect), from: nil)
            let visible = view.visibleRect
            let anchor = NSRect(x: max(visible.minX, min(local.minX, visible.maxX - 20)), y: max(visible.minY, min(local.minY, visible.maxY - 20)), width: 20, height: 20)
            tools.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
        }

    }
}


private struct PassageTools: View {
    var apply: (String, Bool) -> Void
    @State private var direction = ""
    @State private var remember = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected passage").font(.system(size: 11, weight: .medium))
                Spacer()
                Menu {
                    ForEach(DraftAdjustments.all, id: \.0) { item in
                        Button(item.0) { apply(item.1, remember) }
                    }
                } label: { Label("Rewrite", systemImage: "sparkles") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Rewrite selected passage")
            }
            HStack {
                TextField("Describe your change…", text: $direction).textFieldStyle(.plain).onSubmit { submit() }
                Button(action: submit) { Image(systemName: "arrow.up") }.disabled(direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Apply to selected passage")
            }.padding(9).background(Palette.tile).clipShape(RoundedRectangle(cornerRadius: 6))
            Toggle("Remember this direction for this project", isOn: $remember).toggleStyle(.checkbox).font(.system(size: 10))
        }.padding(16).frame(width: 300).background(Palette.panel).foregroundStyle(Palette.text).preferredColorScheme(.dark)
    }
    private func submit() { let text = direction.trimmingCharacters(in: .whitespacesAndNewlines); if !text.isEmpty { apply(text, remember) } }
}

private final class ChangeGlow: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
