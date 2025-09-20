import SwiftUI
import Combine

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: SnapshotService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Logging") {
                    Picker("Level", selection: $settings.loggingLevel) {
                        ForEach(AppSettings.LoggingLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Maintenance") {
                    Button(role: .destructive) {
                        store.clearAllData()
                    } label: {
                        Text("Clear Stored Devices")
                    }
                }
            }
            .navigationTitle("Settings")
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
#endif
        }
        .frame(minWidth: 400, minHeight: 250)
    }
}
