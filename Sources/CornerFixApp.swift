import SwiftUI
import AppKit

@main
struct CornerFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var prefs = Preferences()

    var body: some Scene {
        MenuBarExtra("CornerFix", systemImage: "square.tophalf.filled") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable corner caps", isOn: $prefs.enabled)
                    .onChange(of: prefs.enabled) { _ in OverlayManager.shared.refreshOverlays(prefs: prefs) }

                HStack { Text("Cap size"); Spacer(); Slider(value: $prefs.capSize, in: 2...30, step: 1) { Text("Cap size") }.frame(width: 180) }
                    .onChange(of: prefs.capSize) { _ in OverlayManager.shared.updateCaps() }

                Picker("Color mode", selection: $prefs.colorMode) {
                    Text("Auto (match menu bar)").tag(ColorMode.auto)
                    Text("Custom color").tag(ColorMode.custom)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: prefs.colorMode) { _ in OverlayManager.shared.updateCaps() }

                if prefs.colorMode == .custom {
                    ColorPicker("Cap color", selection: $prefs.customColor)
                        .onChange(of: prefs.customColor) { _ in OverlayManager.shared.updateCaps() }
                }

                Divider()
                Button("Refresh displays") { OverlayManager.shared.refreshOverlays(prefs: prefs) }
                Button("Launch at login…", action: { LaunchAtLogin.toggle() })
                Divider()
                Button("Quit CornerFix") { NSApp.terminate(nil) }
            }
            .padding(12)
            .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        OverlayManager.shared.start()
    }
}
