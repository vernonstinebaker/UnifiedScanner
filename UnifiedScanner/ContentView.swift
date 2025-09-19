import SwiftUI

struct ContentView: View {
    @ObservedObject var store: DeviceSnapshotStore
    @ObservedObject var progress: ScanProgress
    @State private var selectedID: String? = nil
    @State private var showDetailSheet: Bool = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isCompact {
                NavigationStack {
                     VStack(alignment: .leading, spacing: 8) {
                        if progress.started && !progress.finished {
                            ProgressView(value: Double(progress.completedHosts), total: Double(max(progress.totalHosts, 1)))
                                .progressViewStyle(.linear)
                            HStack(spacing: 4) {
                                Text("Scanning \(progress.completedHosts)/\(progress.totalHosts) hosts")
                                Text("\(progress.successHosts) responsive").foregroundStyle(.secondary)
                            }.font(.caption)
                        } else if progress.finished {
                            Text("Scan complete: \(progress.successHosts) responsive hosts").font(.caption).foregroundStyle(.secondary)
                        }
                        List(store.devices, id: \.id) { device in
                            Button {
                                selectedID = device.id
                                showDetailSheet = true
                            } label: {
                                DeviceRowView(device: device)
                            }
                            .buttonStyle(.plain)
                        }
                     }
                    .navigationTitle("Devices")
                    .sheet(isPresented: $showDetailSheet) {
                        if let id = selectedID, let device = store.devices.first(where: { $0.id == id }) {
                            NavigationStack {
                                UnifiedDeviceDetail(device: device)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Done") { showDetailSheet = false }
                                        }
                                    }
                            }
                        }
                    }
                }
            } else {
                NavigationSplitView {
                     VStack(alignment: .leading, spacing: 8) {
                        if progress.started && !progress.finished {
                            ProgressView(value: Double(progress.completedHosts), total: Double(max(progress.totalHosts, 1)))
                                .progressViewStyle(.linear)
                            HStack(spacing: 4) {
                                Text("Scanning \(progress.completedHosts)/\(progress.totalHosts) hosts")
                                Text("\(progress.successHosts) responsive").foregroundStyle(.secondary)
                            }.font(.caption)
                        } else if progress.finished {
                            Text("Scan complete: \(progress.successHosts) responsive hosts").font(.caption).foregroundStyle(.secondary)
                        }
                        List(selection: $selectedID) {
                            ForEach(store.devices, id: \.id) { device in
                                NavigationLink(value: device.id) {
                                    DeviceRowView(device: device)
                                }
                            }
                        }
                     }
                    .navigationDestination(for: String.self) { id in
                        if let device = store.devices.first(where: { $0.id == id }) {
                            UnifiedDeviceDetail(device: device)
                        }
                    }
                    .navigationTitle("Devices")
                } detail: {
                    if let id = selectedID, let device = store.devices.first(where: { $0.id == id }) {
                        UnifiedDeviceDetail(device: device)
                    } else {
                        VStack { Text("Select a device").foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}


