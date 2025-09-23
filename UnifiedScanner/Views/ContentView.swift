import SwiftUI

// Rebuilt clean ContentView after prior corruption. Device selection now ID-based.
struct ContentView: View {
    // Services / Stores
    @ObservedObject var store: SnapshotService
    @ObservedObject var progress: ScanProgress
    @ObservedObject var settings: AppSettings

    // Scan / Bonjour control
    @Binding var isBonjourRunning: Bool
    @Binding var isScanRunning: Bool
    let startBonjour: () -> Void
    let stopBonjour: () -> Void
    let startScan: () -> Void
    let stopScan: () -> Void
    let saveSnapshot: () -> Void

    // External settings trigger (menu on macOS / gear button on iOS)
    @Binding var showSettingsFromMenu: Bool

    // UI State
    @State private var selectedDeviceID: String? = nil
    @State private var sheetDeviceSnapshot: Device? = nil // For compact layout sheet(item:)
    @State private var showSettingsSheet: Bool = false // Used in regular (macOS / large) layout
    @StateObject private var networkInfo = NetworkInfoService()

    // Environment
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase

    // Layout helpers
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // Stats
    private var deviceCount: Int { store.devices.count }
    private var onlineCount: Int { store.devices.filter { $0.isOnline }.count }
    private var serviceCount: Int { store.devices.reduce(0) { $0 + $1.displayServices.count } }

    // MARK: - Body
    var body: some View {
        Group {
            if isCompact { compactLayout } else { regularLayout }
        }
#if os(macOS)
        .background(Theme.color(.bgRoot))
#else
        .background(Theme.color(.bgRoot).ignoresSafeArea())
#endif
        .onAppear { networkInfo.refresh() }
        .onChange(of: scenePhase) { _, newPhase in if newPhase == .active { networkInfo.refresh() } }
        .onChange(of: isScanRunning) { _, _ in networkInfo.refresh() }
        .onChange(of: isBonjourRunning) { _, _ in networkInfo.refresh() }
        .onChange(of: selectedDeviceID) { old, new in
            LoggingService.debug("selection change old=\(old ?? "nil") new=\(new ?? "nil")", category: .general)
        }
    }

    // MARK: - Compact Layout (iPhone style)
    private var compactLayout: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.space(.md)) {
                StatusSectionView(progress: progress, networkInfo: networkInfo, settings: settings)
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.top, Theme.space(.lg))
                ZStack(alignment: .bottom) {
                    DeviceListView(store: store, selectedDeviceID: $selectedDeviceID, mode: .compact)
                    SummaryFooterView(deviceCount: deviceCount, onlineCount: onlineCount, serviceCount: serviceCount)
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.bottom, Theme.space(.lg))
                }
            }
            .background(Theme.color(.bgRoot))
            .navigationTitle("Devices")
            .toolbar { ToolbarView.toolbarContent(isBonjourRunning: $isBonjourRunning, isScanRunning: $isScanRunning, startBonjour: startBonjour, stopBonjour: stopBonjour, startScan: startScan, stopScan: stopScan, saveSnapshot: saveSnapshot, showSettings: $showSettingsFromMenu) }
            .sheet(isPresented: $showSettingsFromMenu) { SettingsView(settings: settings, store: store) }
            .sheet(item: $sheetDeviceSnapshot) { dev in
                DeviceDetailSheet(device: dev, settings: settings)
            }
#if os(macOS)
            .toolbarColorScheme(.dark)
#endif
        }
    }

    // MARK: - Regular Layout (Sidebar + Detail)
    private var regularLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .background(Theme.color(.bgRoot))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.space(.md)) {
            StatusSectionView(progress: progress, networkInfo: networkInfo, settings: settings)
                .padding(.horizontal, Theme.space(.lg))
                .padding(.top, Theme.space(.lg))
            ZStack(alignment: .bottom) {
                DeviceListView(store: store, selectedDeviceID: $selectedDeviceID, mode: .sidebar)
                SummaryFooterView(deviceCount: deviceCount, onlineCount: onlineCount, serviceCount: serviceCount)
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.bottom, Theme.space(.lg))
            }
        }
        .background(Theme.color(.bgRoot))
        .navigationDestination(for: String.self) { deviceID in
            if let device = store.devices.first(where: { $0.id == deviceID }) {
                UnifiedDeviceDetail(device: device, settings: settings)
            } else {
                Text("Device not found").foregroundColor(Theme.color(.textSecondary))
            }
        }
        .navigationTitle("Devices")
        .toolbar { ToolbarView.toolbarContent(isBonjourRunning: $isBonjourRunning, isScanRunning: $isScanRunning, startBonjour: startBonjour, stopBonjour: stopBonjour, startScan: startScan, stopScan: stopScan, saveSnapshot: saveSnapshot, showSettings: $showSettingsSheet) }
        .sheet(isPresented: $showSettingsSheet) { SettingsView(settings: settings, store: store) }
#if os(macOS)
        .toolbarColorScheme(.dark)
#endif
    }

    // Detail panel (regular layout)
    private var detailView: some View {
        Group {
            if let id = selectedDeviceID, let device = store.devices.first(where: { $0.id == id }) {
                UnifiedDeviceDetail(device: device, settings: settings)
            } else if selectedDeviceID != nil {
                placeholderMessage("Device not found")
            } else {
                placeholderMessage("Select a device")
            }
        }
    }

    // MARK: - Device Lists
    private var deviceListCompact: some View {
        List {
            ForEach(store.devices, id: \.id) { device in
                Button {
                    let currentCount = store.devices.count
                    LoggingService.debug("tap:first row device id=\(device.id) before selection count=\(currentCount)", category: .general)
                    selectedDeviceID = device.id
                    sheetDeviceSnapshot = device // capture snapshot
                    LoggingService.debug("presenting sheet snapshot id=\(device.id)", category: .general)
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
    }

    // MARK: - Sheet Content (compact detail)
    private func sheetContent(for snapshot: Device) -> some View {
        DeviceDetailSheet(device: snapshot, settings: settings)
    }

    // MARK: - Shared UI Sections
    private func placeholderMessage(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.color(.textSecondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.color(.bgRoot))
    }

    private var progressText: String {
        switch progress.phase {
        case .pinging: return "Pinging \(progress.completedHosts)/\(progress.totalHosts) hosts"
        case .mdnsWarmup: return "Warming up mDNS…"
        default: return "Scanning \(progress.completedHosts)/\(progress.totalHosts) hosts"
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
                indeterminateProgress("Priming ARP table…")
            } else if progress.phase == .enumerating {
                indeterminateProgress("Enumerating subnet…")
            } else if progress.phase == .arpRefresh && !progress.finished {
                indeterminateProgress("Refreshing ARP entries…")
            } else if progress.finished {
                Text("Scan complete: \(progress.successHosts) responsive hosts")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
            }
        }
    }

    private func indeterminateProgress(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(.xs)) {
            ProgressView().tint(Theme.color(.accentPrimary))
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
        }
    }

    private var summaryFooter: some View {
        SummaryFooterView(deviceCount: deviceCount, onlineCount: onlineCount, serviceCount: serviceCount)
    }

    private func dismissSheetSelection() {
        selectedDeviceID = nil
        sheetDeviceSnapshot = nil
    }
}


