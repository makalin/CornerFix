import SwiftUI

enum ColorMode: String, Codable, CaseIterable, Identifiable { case auto, custom; var id: String { rawValue } }

final class Preferences: ObservableObject {
    @AppStorage("enabled") var enabled: Bool = true
    @AppStorage("capSize") var capSize: Double = 12
    @AppStorage("colorMode") var colorModeRaw: String = ColorMode.auto.rawValue
    @AppStorage("customColor") var customColorData: Data = try! NSKeyedArchiver.archivedData(withRootObject: NSColor.black, requiringSecureCoding: false)

    var colorMode: ColorMode {
        get { ColorMode(rawValue: colorModeRaw) ?? .auto }
        set { colorModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var customColor: Color {
        get {
            if let ns = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(customColorData) as? NSColor {
                return Color(nsColor: ns)
            }
            return .black
        }
        set {
            let ns = NSColor(newValue)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: false) {
                customColorData = data; objectWillChange.send()
            }
        }
    }
}

extension NSColor {
    convenience init(_ swiftUIColor: Color) {
        if let cg = swiftUIColor.cgColor { self.init(cgColor: cg)! } else { self.init(white: 0, alpha: 1) }
    }
}
