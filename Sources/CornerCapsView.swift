import AppKit

final class CornerCapsView: NSView {
    var capSize: CGFloat = 12
    var capColor: NSColor = .black

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(capColor.cgColor)

        let w = bounds.width
        let h = bounds.height
        let s = capSize

        // Four corner squares
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))                   // Top-left
        ctx.fill(CGRect(x: w - s, y: 0, width: s, height: s))               // Top-right
        ctx.fill(CGRect(x: 0, y: h - s, width: s, height: s))               // Bottom-left
        ctx.fill(CGRect(x: w - s, y: h - s, width: s, height: s))           // Bottom-right

        // Edge strips to fully mask aggressive rounding
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: h))                   // Left strip
        ctx.fill(CGRect(x: w - s, y: 0, width: s, height: h))               // Right strip
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: s))                   // Top strip
        ctx.fill(CGRect(x: 0, y: h - s, width: w, height: s))               // Bottom strip
    }
}
