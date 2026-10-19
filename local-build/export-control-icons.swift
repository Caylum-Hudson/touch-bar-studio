import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: directory.appendingPathComponent("symbols.json"))
let symbols = try JSONDecoder().decode([String:String].self, from:data)
for (key, name) in symbols {
    guard let source = NSImage(systemSymbolName:name, accessibilityDescription:nil) else { fatalError("Missing symbol: \(name)") }
    let image = NSImage(size:NSSize(width:48,height:48))
    image.lockFocus()
    NSColor.white.set()
    let configured = source.withSymbolConfiguration(.init(pointSize:25,weight:.medium)) ?? source
    let size = configured.size
    let scale = min(38/size.width,38/size.height)
    let target = NSRect(x:(48-size.width*scale)/2,y:(48-size.height*scale)/2,width:size.width*scale,height:size.height*scale)
    configured.draw(in:target)
    NSColor.white.set()
    target.fill(using:.sourceAtop)
    image.unlockFocus()
    guard let tiff=image.tiffRepresentation, let rep=NSBitmapImageRep(data:tiff), let png=rep.representation(using:.png,properties:[:]) else { fatalError(key) }
    try png.write(to:directory.appendingPathComponent(key+".png"))
}
print("Exported \(symbols.count) macOS control icons")
