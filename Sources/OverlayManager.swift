import AppKit

final class OverlayManager {
    static let shared = OverlayManager()
    private init() {}

    private var observers: [NSObjectProtocol] = []
    private var windows: [OverlayWindow] = []
    private var prefs: Preferences = Preferences()

    func start() {
        installObservers()
        refreshOverlays(prefs: prefs)
    }

    func installObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateCaps() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshOverlays(prefs: self?.prefs ?? Preferences()) })
        observers.append(nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateCaps() })
    }

    func refreshOverlays(prefs: Preferences) {
        self.prefs = prefs
        windows.forEach { $0.close() }
        windows.removeAll()
        guard prefs.enabled else { return }
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen)
            w.capSize = CGFloat(prefs.capSize)
            w.capColor = effectiveColor()
            w.isReleasedWhenClosed = false
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func updateCaps() {
        for w in windows {
            w.capSize = CGFloat(prefs.capSize)
            w.capColor = effectiveColor()
            w.setFrame(w.screen?.frame ?? .zero, display: true)
            w.contentView?.needsDisplay = true
        }
    }

    private func effectiveColor() -> NSColor {
        switch prefs.colorMode {
        case .auto:
            let appearance = NSApp.effectiveAppearance
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.black : NSColor.white
        case .custom:
            return NSColor(prefs.customColor)
        }
    }
}
