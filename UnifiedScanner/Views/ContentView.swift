import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SnapshotService
    @ObservedObject var progress: ScanProgress
    @ObservedObject var settings: AppSettings
    @Binding var isBonjourRunning: Bool
    @Binding var isScanRunning: Bool
    let startBonjour: () -> Void
    let stopBonjour: () -> Void
    let startScan: () -> Void
    let stopScan: () -> Void
    let saveSnapshot: () -> Void
    @Binding var showSettingsFromMenu: Bool
    @State private var selectedDevice: Device? = nil
    @State private var showDetailSheet: Bool = false
    @State private var showSettings: Bool = false
    @StateObject private var networkInfo = NetworkInfoService()

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Environment(\.scenePhase) private var scenePhase

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
#if os(macOS)
        .background(Theme.color(.bgRoot))
#else
        .background(Theme.color(.bgRoot).ignoresSafeArea())
#endif
        .onAppear { networkInfo.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                networkInfo.refresh()
            }
        }
        .onChange(of: isScanRunning) { _, _ in networkInfo.refresh() }
        .onChange(of: isBonjourRunning) { _, _ in networkInfo.refresh() }
    }

    private var compactLayout: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.space(.md)) {
                statusSection
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.top, Theme.space(.lg))
				ZStack(alignment: .bottom) {
                    List {
ForEach(store.devices, id: \.id) { device in
    Button {
        selectedDevice = device
        showDetailSheet = true
    } label: {
        DeviceRowView(device: device, isSelected: false)
    }
    .buttonStyle(.plain)
.listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.color(.bgRoot))
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
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { isBonjourRunning ? stopBonjour() : startBonjour() }) {
                        Label(bonjourButtonLabel, systemImage: bonjourButtonIcon)
                    }
#if os(macOS)
                    .help(bonjourButtonLabel)
#endif
                    Button(action: { isScanRunning ? stopScan() : startScan() }) {
                        Label(scanButtonLabel, systemImage: scanButtonIcon)
                    }
#if os(macOS)
                    .help(scanButtonLabel)
#endif
                    Button(action: saveSnapshot) {
                        Label("Save", systemImage: "externaldrive")
                    }
#if os(macOS)
                    .help("Persist snapshot now")
#endif
                    Button { showSettingsFromMenu = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
            .sheet(isPresented: $showSettingsFromMenu) {
                SettingsView(settings: settings, store: store)
            }
            .sheet(isPresented: $showDetailSheet) {
                if let device = selectedDevice {
                    NavigationStack {
                        UnifiedDeviceDetail(device: device, settings: settings)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { 
                                        showDetailSheet = false
                                        selectedDevice = nil
                                    }
                                }
                            }
                        }
                    }
                }
#if os(macOS)
            .toolbarColorScheme(.dark)
#endif
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(Theme.color(.bgRoot))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.space(.md)) {
            statusSection
                .padding(.horizontal, Theme.space(.lg))
                .padding(.top, Theme.space(.lg))
            ZStack(alignment: .bottom) {
                List(selection: $selectedDevice) {
                    ForEach(store.devices) { device in
                        NavigationLink(value: device) {
                            DeviceRowView(device: device, isSelected: selectedDevice?.id == device.id)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.color(.bgRoot))
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
        .navigationDestination(for: Device.self) { device in
            UnifiedDeviceDetail(device: device, settings: settings)
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { isBonjourRunning ? stopBonjour() : startBonjour() }) {
                    Label(bonjourButtonLabel, systemImage: bonjourButtonIcon)
                }
#if os(macOS)
                .help(bonjourButtonLabel)
#endif
                Button(action: { isScanRunning ? stopScan() : startScan() }) {
                    Label(scanButtonLabel, systemImage: scanButtonIcon)
                }
#if os(macOS)
                .help(scanButtonLabel)
#endif
                Button(action: saveSnapshot) {
                    Label("Save", systemImage: "externaldrive")
                }
#if os(macOS)
                .help("Persist snapshot now")
#endif
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, store: store)
        }
#if os(macOS)
        .toolbarColorScheme(.dark)
#endif
    }

    private var detail: some View {
        Group {
            if let device = selectedDevice {
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

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            networkStatusHeader
            progressSection
        }
    }

    private var networkStatusHeader: some View {
        VStack(alignment: .leading, spacing: Theme.space(.xs)) {
            HStack(spacing: Theme.space(.lg)) {
                statusIcon(icon: "globe", value: networkInfo.networkDescription, usesMono: true)
                statusIcon(icon: "dot.radiowaves.left.and.right", value: networkInfo.ipDescription, usesMono: true)
                statusIcon(icon: "wifi", value: networkInfo.wifiDisplay, usesMono: false)
            }
            if settings.showInterface, let interface = networkInfo.interface {
                Text("Interface: \(interface.name)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textTertiary))
            }
        }
        .cardStyle()
    }

    private func statusIcon(icon: String, value: String, usesMono: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.space(.xs)) {
            Image(systemName: icon)
                .foregroundColor(Theme.color(.accentPrimary))
                .font(.system(size: 16, weight: .semibold))
            Text(value)
                .font(usesMono ? Theme.Typography.mono : Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
                .lineLimit(1)
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

    private var bonjourButtonLabel: String { isBonjourRunning ? "Stop Bonjour" : "Start Bonjour" }
    private var bonjourButtonIcon: String { isBonjourRunning ? "wifi.slash" : "dot.radiowaves.left.and.right" }
    private var scanButtonLabel: String { isScanRunning ? "Stop Scan" : "Run Scan" }
    private var scanButtonIcon: String { isScanRunning ? "stop.circle" : "arrow.clockwise" }

    private func toolbarButton(title: String,
                               systemImage: String,
                               isActive: Bool,
                               help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
#if os(macOS)
        .help(help)
#endif
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
