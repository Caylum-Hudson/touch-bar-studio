import Cocoa

/// Native symbols shared with the editor through its bundled icon catalog.
enum StudioControlStyle {
    static let symbols: [String:String] = {
        guard let url = Bundle.main.url(forResource:"symbols",withExtension:"json",subdirectory:"WebApp/control-icons"),
              let data = try? Data(contentsOf:url),
              let values = try? JSONDecoder().decode([String:String].self,from:data) else { return [:] }
        return values
    }()

    static func image(_ key: String, fallback: NSImage? = nil) -> NSImage? {
        guard let symbol = symbols[key], let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil) else { return fallback }
        image.size = NSSize(width:20,height:20)
        image.isTemplate = true
        return image
    }
}
