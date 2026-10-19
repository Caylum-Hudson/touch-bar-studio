import Cocoa

/// A shared 1085-unit layout scales to the width macOS gives the custom bar.
enum StudioLayout {
    static let width: CGFloat = 1085
    static func precise(_ definitions: [BarItemDefinition]) -> Bool {
        definitions.contains { if case .studioPosition? = $0.additionalParameters[.studioPosition] { return true }; return false }
    }
    static func frames(_ definitions: [BarItemDefinition]) -> [CGRect] {
        var frames = Array(repeating:CGRect.zero,count:definitions.count)
        for alignment: Align in [.left,.center,.right] {
            let indices = definitions.indices.filter { definitions[$0].align == alignment }
            func itemWidth(_ index: Int) -> CGFloat {
                if case let .width(value)? = definitions[index].additionalParameters[.width] { return min(width,max(24,value)) }
                return 64
            }
            let total = indices.reduce(CGFloat(0)) { $0 + itemWidth($1) } + CGFloat(max(0,indices.count-1))*4
            var cursor: CGFloat = alignment == .left ? 0 : alignment == .right ? width-total : (width-total)/2
            for index in indices {
                let itemWidth = itemWidth(index)
                var x = cursor
                if case let .studioPosition(value)? = definitions[index].additionalParameters[.studioPosition] { x = value }
                frames[index] = CGRect(x:min(width-itemWidth,max(0,x.rounded())),y:0,width:itemWidth,height:30)
                cursor += itemWidth+4
            }
        }
        return frames
    }
}

final class StudioPositionedView: NSView {
    private let controlFrames: [CGRect]
    init(views: [NSView], frames: [CGRect]) {
        controlFrames = frames
        super.init(frame:NSRect(x:0,y:0,width:StudioLayout.width,height:30))
        for view in views {
            NSLayoutConstraint.deactivate(view.constraints.filter { $0.firstAttribute == .width })
            addSubview(view)
        }
        setContentHuggingPriority(NSLayoutConstraint.Priority(1),for:.horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1),for:.horizontal)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { NSSize(width:StudioLayout.width,height:30) }
    override func layout() {
        super.layout()
        let scale = bounds.width/StudioLayout.width
        for (view,frame) in zip(subviews,controlFrames) {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.frame = NSRect(x:frame.minX*scale,y:0,width:frame.width*scale,height:bounds.height)
        }
    }
}
