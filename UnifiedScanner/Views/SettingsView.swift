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
                    .padding(.horizontal, Theme.space(.lg))
                    
                    #if os(macOS)
                    let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2)
                    #else
                    let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 1)
                    #endif
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(LoggingService.Category.allCases) { category in
                            HStack {
                                Text(category.displayName)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.color(.textPrimary))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Toggle("", isOn: settings.binding(for: category))
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(.horizontal, Theme.space(.lg))
                }
                .padding(.bottom, Theme.space(.lg))
                Section("Detail View") {
                    Toggle("Show Fingerprints", isOn: $settings.showFingerprints)
                    Toggle("Show Interface", isOn: $settings.showInterface)
                }
                Section("Maintenance") {
                    Button(role: .destructive) {
                        store.clearAllData()
                    } label: {
                        Text("Clear Stored Devices")
                    }
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.bottom, Theme.space(.lg))
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 250)
    }
}
