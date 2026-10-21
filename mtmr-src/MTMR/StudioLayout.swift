import Cocoa

/// A shared 1085-unit layout scales to the width macOS gives the custom bar.
enum StudioLayout {
    static let width: CGFloat = 1085
    static func precise(_ definitions: [BarItemDefinition]) -> Bool {
        definitions.contains { if case .studioPosition? = $0.additionalParameters[.studioPosition] { return true }; return false }
    }
    static func frames(_ definitions: [BarItemDefinition], preferredContentWidths: [Int: CGFloat] = [:]) -> [CGRect] {
        var frames = Array(repeating:CGRect.zero,count:definitions.count)
        func isAutoResizingDock(_ index: Int) -> Bool {
            if case let .dock(autoResize: enabled, filter: _) = definitions[index].type { return enabled }
            return false
        }
        for alignment: Align in [.left,.center,.right] {
            let indices = definitions.indices.filter { definitions[$0].align == alignment }
            func itemWidth(_ index: Int) -> CGFloat {
                if isAutoResizingDock(index), let preferred = preferredContentWidths[index] {
                    return min(width, max(0, preferred))
                }
                let configured: CGFloat
                if case let .width(value)? = definitions[index].additionalParameters[.width] {
                    configured = min(width, max(24, value))
                } else {
                    configured = 64
                }
                return min(width, max(configured, preferredContentWidths[index] ?? 0))
            }
            let total = indices.reduce(CGFloat(0)) { $0 + itemWidth($1) } + CGFloat(max(0,indices.count-1))*4
            var cursor: CGFloat = alignment == .left ? 0 : alignment == .right ? width-total : (width-total)/2
            for index in indices {
                let itemWidth = itemWidth(index)
                var x = cursor
                let hasSavedPosition: Bool
                if case let .studioPosition(value)? = definitions[index].additionalParameters[.studioPosition] {
                    x = value
                    hasSavedPosition = true
                } else {
                    hasSavedPosition = false
                }
                let frameX: CGFloat
                if hasSavedPosition {
                    // Keep a user's explicit X even when a wider live label reaches
                    // the edge; clipping is preferable to silently moving controls.
                    frameX = max(0, x.rounded())
                } else {
                    let maxX = isAutoResizingDock(index) ? width : width-itemWidth
                    frameX = min(maxX, max(0, x.rounded()))
                }
                frames[index] = CGRect(x:frameX,y:0,width:itemWidth,height:30)
                cursor += itemWidth+4
            }
        }
        for index in definitions.indices where isAutoResizingDock(index) {
            let x = frames[index].minX
            let nextItemX = frames.indices.filter { $0 != index && frames[$0].minX >= x }
                .map { frames[$0].minX }.min()
            let limit = nextItemX ?? width
            let gap: CGFloat = nextItemX == nil ? 0 : 4
            let available = max(0, limit - x - gap)
            frames[index].size.width = min(frames[index].width, available)
        }
        return frames
    }
}

final class StudioPositionedView: NSView {
    private let controlFrames: [CGRect]
    private let frameProvider: ([Int: CGFloat]) -> [CGRect]
    private var autoResizingDocks: [Int: AppScrubberTouchBarItem] = [:]
    private var contentWidthItems: [Int: CustomButtonTouchBarItem] = [:]
    init(views: [NSView], frames: [CGRect], frameProvider: @escaping ([Int: CGFloat]) -> [CGRect]) {
        controlFrames = frames
        self.frameProvider = frameProvider
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
    func attachAutoResizingDock(_ dock: AppScrubberTouchBarItem, at index: Int) {
        autoResizingDocks[index] = dock
        dock.usePositionedWidth { [weak self] in self?.needsLayout = true }
        needsLayout = true
    }
    func attachContentWidthItem(_ item: CustomButtonTouchBarItem, at index: Int) {
        contentWidthItems[index] = item
        item.studioContentWidthDidChange = { [weak self] in self?.needsLayout = true }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let scale = max(0.01, bounds.width/StudioLayout.width)
        var preferredWidths = contentWidthItems.mapValues { $0.studioNaturalContentWidth / scale }
        for (index, dock) in autoResizingDocks {
            preferredWidths[index] = dock.naturalContentWidth / scale
        }
        let providedFrames = frameProvider(preferredWidths)
        let frames = providedFrames.count == subviews.count ? providedFrames : controlFrames
        for (index, (view,frame)) in zip(subviews,frames).enumerated() {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.frame = NSRect(x:frame.minX*scale,y:0,width:frame.width*scale,height:bounds.height)
            autoResizingDocks[index]?.fitContent(to: frame.width*scale)
        }
    }
}
