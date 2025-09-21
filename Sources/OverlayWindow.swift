import AppKit

final class OverlayWindow: NSWindow {
    private let cornerView = CornerCapsView()
    var capSize: CGFloat = 12 { didSet { cornerView.capSize = capSize; cornerView.needsDisplay = true } }
    var capColor: NSColor = .black { didSet { cornerView.capColor = capColor; cornerView.needsDisplay = true } }

    convenience init(screen: NSScreen) {
        let frame = screen.frame
        self.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = cornerView
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
