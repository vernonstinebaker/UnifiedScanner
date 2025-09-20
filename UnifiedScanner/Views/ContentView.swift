import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SnapshotService
    @ObservedObject var progress: ScanProgress
    @ObservedObject var settings: AppSettings
    @State private var selectedID: String? = nil
    @State private var showDetailSheet: Bool = false
    @State private var showSettings: Bool = false

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

    private var deviceCount: Int { store.devices.count }
    private var onlineCount: Int { store.devices.filter { $0.isOnline }.count }
    private var serviceCount: Int { store.devices.reduce(0) { $0 + $1.displayServices.count } }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .background(Theme.color(.bgRoot).ignoresSafeArea())
    }

    private var compactLayout: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.space(.md)) {
                progressSection
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.top, Theme.space(.lg))

                ZStack(alignment: .bottom) {
                    List {
                        ForEach(store.devices, id: \.id) { device in
                            Button {
                                selectedID = device.id
                                showDetailSheet = true
                            } label: {
                                DeviceRowView(device: device)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .background(Theme.color(.bgRoot))
                    .padding(.bottom, Theme.space(.xxxl))

                    summaryFooter
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.bottom, Theme.space(.lg))
                }
            }
            .background(Theme.color(.bgRoot))
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings, store: store)
            }
            .sheet(isPresented: $showDetailSheet) {
                if let id = selectedID, let device = store.devices.first(where: { $0.id == id }) {
                    NavigationStack {
                        UnifiedDeviceDetail(device: device, settings: settings)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showDetailSheet = false }
                                }
                            }
                    }
                }
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: Theme.space(.md)) {
                progressSection
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.top, Theme.space(.lg))

                ZStack(alignment: .bottom) {
                    List(selection: $selectedID) {
                        ForEach(store.devices, id: \.id) { device in
                            NavigationLink(value: device.id) {
                                DeviceRowView(device: device)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .background(Theme.color(.bgRoot))
                    .padding(.bottom, Theme.space(.xxxl))

                    summaryFooter
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.bottom, Theme.space(.lg))
                }
            }
            .background(Theme.color(.bgRoot))
            .navigationDestination(for: String.self) { id in
                if let device = store.devices.first(where: { $0.id == id }) {
                    UnifiedDeviceDetail(device: device, settings: settings)
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings, store: store)
            }
        } detail: {
            if let id = selectedID, let device = store.devices.first(where: { $0.id == id }) {
                UnifiedDeviceDetail(device: device, settings: settings)
            } else {
                VStack {
                    Text("Select a device")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.color(.textSecondary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.color(.bgRoot))
            }
        }
        .background(Theme.color(.bgRoot))
    }

    private var progressText: String {
        switch progress.phase {
        case .pinging:
            return "Pinging \(progress.completedHosts)/\(progress.totalHosts) hosts"
        case .mdnsWarmup:
            return "Warming up mDNS…"
        default:
            return "Scanning \(progress.completedHosts)/\(progress.totalHosts) hosts"
        }
    }

    private var progressSection: some View {
        Group {
            if progress.started && !progress.finished {
                VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                    ProgressView(value: Double(progress.completedHosts), total: Double(max(progress.totalHosts, 1)))
                        .tint(Theme.color(.accentPrimary))
                    HStack(spacing: Theme.space(.sm)) {
                        Text(progressText)
                        Text("\(progress.successHosts) responsive")
                            .foregroundColor(Theme.color(.textSecondary))
                    }
                     .font(Theme.Typography.caption)
                     .foregroundColor(Theme.color(.textSecondary))
                 }
             } else if progress.phase == .arpPriming {
                 VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                     ProgressView()
                         .tint(Theme.color(.accentPrimary))
                     Text("Priming ARP table…")
                         .font(Theme.Typography.caption)
                         .foregroundColor(Theme.color(.textSecondary))
                 }
             } else if progress.phase == .enumerating {
                 VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                     ProgressView()
                         .tint(Theme.color(.accentPrimary))
                     Text("Enumerating subnet…")
                         .font(Theme.Typography.caption)
                         .foregroundColor(Theme.color(.textSecondary))
                 }
             } else if progress.phase == .arpRefresh && !progress.finished {
                 VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                     ProgressView()
                         .tint(Theme.color(.accentPrimary))
                     Text("Refreshing ARP entries…")
                         .font(Theme.Typography.caption)
                         .foregroundColor(Theme.color(.textSecondary))
                 }
             } else if progress.finished {
                Text("Scan complete: \(progress.successHosts) responsive hosts")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
            }
        }
    }

    private var summaryFooter: some View {
        HStack {
            StatBlock(count: deviceCount, title: "Devices")
            Spacer()
            StatBlock(count: onlineCount, title: "Online")
            Spacer()
            StatBlock(count: serviceCount, title: "Services")
        }
        .padding(.horizontal, Theme.space(.xl))
        .padding(.vertical, Theme.space(.lg))
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.radius(.xl))
    }
}

private struct StatBlock: View {
    let count: Int
    let title: String

    var body: some View {
        VStack(spacing: Theme.space(.xs)) {
            Text("\(count)")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.color(.accentPrimary))
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
        }
    }
}
