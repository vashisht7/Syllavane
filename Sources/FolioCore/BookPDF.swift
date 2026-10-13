import Foundation
import AppKit
import CoreText

public struct BookTypography: Codable, Equatable, Sendable {
    public var themeName = "Classic"
    public var fontName: String = "Baskerville"
    public var fontSize: CGFloat = 12
    public var lineSpacing: CGFloat = 3
    public var paragraphSpacing: CGFloat = 0
    public var indent: CGFloat = 16
    public var margin: CGFloat = 48
    public init() {}
    public static func preset(_ name: String) -> BookTypography {
        var style = BookTypography(); style.themeName = name
        if name == "Modern" { style.fontName = "Georgia"; style.fontSize = 11.5; style.paragraphSpacing = 6; style.indent = 0 }
        if name == "Airy" { style.fontName = "Palatino"; style.lineSpacing = 5; style.paragraphSpacing = 7; style.indent = 0; style.margin = 54 }
        return style
    }
}
public enum BookPDF {
    public static func render(project: StoryProject, chapterID: UUID? = nil, includeDrafts: Bool = false, typography: BookTypography = BookTypography()) throws -> Data {
        guard typography.fontSize.isFinite, (8...24).contains(typography.fontSize),
              typography.margin.isFinite, (24...100).contains(typography.margin),
              typography.indent.isFinite, (0...50).contains(typography.indent),
              typography.lineSpacing.isFinite, (0...24).contains(typography.lineSpacing),
              typography.paragraphSpacing.isFinite, (0...30).contains(typography.paragraphSpacing) else {
            throw FolioError.message("The imported page settings are invalid. Choose a theme preset before exporting.")
        }
        if let chapterID, !project.chapters.contains(where: { $0.id == chapterID }) { throw FolioError.message("The selected chapter is unavailable. Choose another chapter.") }
        let data = NSMutableData()
        let isBook = project.writingMode == .book
        let width: CGFloat = isBook ? 432 : 595
        let height: CGFloat = isBook ? 648 : 842
        var pageRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &pageRect, [kCGPDFContextTitle: project.name] as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        func draw(_ text: String, size: CGFloat, rect: CGRect, centered: Bool = false) {
            let p = NSMutableParagraphStyle(); p.alignment = centered ? .center : .left
            let a = NSAttributedString(string: text, attributes: [.font: NSFont(name: typography.fontName, size: size) ?? NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black, .paragraphStyle: p])
            let setter = CTFramesetterCreateWithAttributedString(a)
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil), context)
        }
        if isBook {
        context.beginPDFPage(nil)
        draw(project.name, size: 28, rect: CGRect(x: 48, y: 275, width: 336, height: 150), centered: true)
        if includeDrafts { draw("Draft preview · includes unaccepted writing", size: 9, rect: CGRect(x: 48, y: 225, width: 336, height: 30), centered: true) }
        context.endPDFPage()
        }
        var number = 0
        for chapter in project.chapters where chapterID == nil || chapter.id == chapterID {
            let body = chapter.scenes.map { scene in includeDrafts ? (scene.pendingDraft ?? scene.text) : scene.text }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
            guard !body.isEmpty else { continue }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .justified; paragraph.lineSpacing = typography.lineSpacing; paragraph.paragraphSpacing = typography.paragraphSpacing; paragraph.firstLineHeadIndent = typography.indent; paragraph.hyphenationFactor = 0.6
            let heading = NSMutableParagraphStyle(); heading.alignment = .center; heading.paragraphSpacing = 20
            let text = NSMutableAttributedString(string: chapter.title + "\n\n", attributes: [.font: NSFont(name: typography.fontName, size: 22) ?? NSFont.systemFont(ofSize: 22), .paragraphStyle: heading, .foregroundColor: NSColor.black])
            let bodyStart = text.length
            let cleanBody = typography.paragraphSpacing == 0 ? body.replacingOccurrences(of: "\n\n", with: "\n") : body
            text.append(NSAttributedString(string: cleanBody, attributes: [.font: NSFont(name: typography.fontName, size: typography.fontSize) ?? NSFont.systemFont(ofSize: typography.fontSize), .paragraphStyle: paragraph, .foregroundColor: NSColor.black]))
            let opening = paragraph.mutableCopy() as! NSMutableParagraphStyle; opening.firstLineHeadIndent = 0
            let firstLength = (cleanBody as NSString).range(of: "\n").location
            text.addAttribute(.paragraphStyle, value: opening, range: NSRange(location: bodyStart, length: firstLength == NSNotFound ? (cleanBody as NSString).length : firstLength))
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            var offset = 0
            while offset < text.length {
                try Task.checkCancellation()
                context.beginPDFPage(nil); number += 1
                draw(project.name, size: 8, rect: CGRect(x: 48, y: height - 38, width: width - 96, height: 16), centered: true)
                let path = CGPath(rect: CGRect(x: typography.margin, y: 52, width: width - typography.margin * 2, height: height - 112), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                CTFrameDraw(frame, context)
                draw(String(number), size: 9, rect: CGRect(x: 48, y: 25, width: width - 96, height: 16), centered: true)
                let length = CTFrameGetVisibleStringRange(frame).length
                context.endPDFPage()
                guard length > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += length
            }
        }
        context.closePDF()
        return data as Data
    }
}
