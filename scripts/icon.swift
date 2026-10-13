import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
 let image = NSImage(size: NSSize(width:size,height:size))
 image.lockFocus()
 let s=CGFloat(size)
 let rect=NSRect(x:s*0.06,y:s*0.06,width:s*0.88,height:s*0.88)
 NSColor(calibratedWhite:0.085,alpha:1).setFill()
 NSBezierPath(roundedRect:rect,xRadius:s*0.2,yRadius:s*0.2).fill()
 NSColor(calibratedWhite:0.23,alpha:1).setStroke()
 let border=NSBezierPath(roundedRect:rect.insetBy(dx:1,dy:1),xRadius:s*0.2,yRadius:s*0.2);border.lineWidth=max(1,s*0.003);border.stroke()
 let attributes:[NSAttributedString.Key:Any]=[.font:NSFont(name:"Baskerville",size:s*0.68) ?? NSFont.systemFont(ofSize:s*0.6),.foregroundColor:NSColor(calibratedWhite:0.88,alpha:1)]
 let letter="s" as NSString
 let measured=letter.size(withAttributes:attributes)
 letter.draw(at:NSPoint(x:(s-measured.width)/2-s*0.015,y:(s-measured.height)/2+s*0.03),withAttributes:attributes)
 NSColor(calibratedWhite:0.43,alpha:1).setStroke()
 let line=NSBezierPath();line.move(to:NSPoint(x:s*0.31,y:s*0.23));line.line(to:NSPoint(x:s*0.69,y:s*0.23));line.lineWidth=max(1,s*0.005);line.stroke()
 image.unlockFocus()
 let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
 try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("icon_\(size).png"))
}
