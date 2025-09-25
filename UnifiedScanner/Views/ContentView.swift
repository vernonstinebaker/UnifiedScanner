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
    @StateObject private var networkInfo: NetworkInfoService
    @StateObject private var statusViewModel: StatusDashboardViewModel

    // Environment
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init(store: SnapshotService,
         progress: ScanProgress,
         settings: AppSettings,
         isBonjourRunning: Binding<Bool>,
         isScanRunning: Binding<Bool>,
         startBonjour: @escaping () -> Void,
         stopBonjour: @escaping () -> Void,
         startScan: @escaping () -> Void,
         stopScan: @escaping () -> Void,
         saveSnapshot: @escaping () -> Void,
         showSettingsFromMenu: Binding<Bool>) {
        self.store = store
        self.progress = progress
        self.settings = settings
        self._isBonjourRunning = isBonjourRunning
        self._isScanRunning = isScanRunning
        self.startBonjour = startBonjour
        self.stopBonjour = stopBonjour
        self.startScan = startScan
        self.stopScan = stopScan
        self.saveSnapshot = saveSnapshot
        self._showSettingsFromMenu = showSettingsFromMenu

        let networkInfoService = NetworkInfoService()
        _networkInfo = StateObject(wrappedValue: networkInfoService)
        _statusViewModel = StateObject(wrappedValue: StatusDashboardViewModel(progress: progress,
                                                                              networkProvider: networkInfoService,
                                                                              settings: settings))
    }

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
        .onAppear { statusViewModel.refreshNetwork() }
        .onChange(of: scenePhase) { _, newPhase in if newPhase == .active { statusViewModel.refreshNetwork() } }
        .onChange(of: isScanRunning) { _, _ in statusViewModel.refreshNetwork() }
        .onChange(of: isBonjourRunning) { _, _ in statusViewModel.refreshNetwork() }
        .onChange(of: selectedDeviceID) { old, new in
            LoggingService.debug("selection change old=\(old ?? "nil") new=\(new ?? "nil")", category: .general)
        }
    }

    // MARK: - Compact Layout (iPhone style)
    private var compactLayout: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.space(.md)) {
                StatusSectionView(viewModel: statusViewModel)
                    .padding(.horizontal, Theme.space(.lg))
                    .padding(.top, Theme.space(.lg))
                ZStack(alignment: .bottom) {
                    DeviceListView(store: store, selectedDeviceID: $selectedDeviceID, sheetDeviceSnapshot: $sheetDeviceSnapshot, mode: .compact)
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
            StatusSectionView(viewModel: statusViewModel)
                .padding(.horizontal, Theme.space(.lg))
                .padding(.top, Theme.space(.lg))
            ZStack(alignment: .bottom) {
                DeviceListView(store: store, selectedDeviceID: $selectedDeviceID, sheetDeviceSnapshot: .constant(nil), mode: .sidebar)
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

    private var summaryFooter: some View {
        SummaryFooterView(deviceCount: deviceCount, onlineCount: onlineCount, serviceCount: serviceCount)
    }

    private func dismissSheetSelection() {
        selectedDeviceID = nil
        sheetDeviceSnapshot = nil
    }
}
