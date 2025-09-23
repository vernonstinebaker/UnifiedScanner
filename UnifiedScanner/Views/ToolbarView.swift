import SwiftUI

@MainActor struct ToolbarView {
    @ToolbarContentBuilder
    static func toolbarContent(isBonjourRunning: Binding<Bool>, isScanRunning: Binding<Bool>, startBonjour: @escaping () -> Void, stopBonjour: @escaping () -> Void, startScan: @escaping () -> Void, stopScan: @escaping () -> Void, saveSnapshot: @escaping () -> Void, showSettings: Binding<Bool>) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { if isBonjourRunning.wrappedValue { stopBonjour() } else { startBonjour() } }) {
                Label(isBonjourRunning.wrappedValue ? "Stop Bonjour" : "Start Bonjour", systemImage: isBonjourRunning.wrappedValue ? "wifi.slash" : "dot.radiowaves.left.and.right")
            }
#if os(macOS)
            .help(isBonjourRunning.wrappedValue ? "Stop Bonjour" : "Start Bonjour")
#endif

            Button(action: { if isScanRunning.wrappedValue { stopScan() } else { startScan() } }) {
                Label(isScanRunning.wrappedValue ? "Stop Scan" : "Run Scan", systemImage: isScanRunning.wrappedValue ? "stop.circle" : "arrow.clockwise")
            }
#if os(macOS)
            .help(isScanRunning.wrappedValue ? "Stop Scan" : "Run Scan")
#endif

            Button(action: saveSnapshot) {
                Label("Save", systemImage: "externaldrive")
            }
#if os(macOS)
            .help("Persist snapshot now")
#endif

            Button { showSettings.wrappedValue = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
#if os(iOS)
            .keyboardShortcut(",", modifiers: .command)
#endif
        }
    }
}
