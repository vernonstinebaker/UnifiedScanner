//
//  UnifiedScannerApp.swift
//  UnifiedScanner
//
//  Created by Vernon Stinebaker on 9/18/25.
//

import SwiftUI

@main
struct UnifiedScannerApp: App {
    private let appEnvironment: AppEnvironment
    private let portScanService: PortScanService
    private let httpFingerprintService: HTTPFingerprintService
    private let sshHostKeyService: SSHHostKeyService
    @StateObject private var snapshotStore: SnapshotService

    init() {
        let environment = AppEnvironment()
        self.appEnvironment = environment
        self.portScanService = environment.makePortScanService()
        self.httpFingerprintService = environment.makeHTTPFingerprintService()
        self.sshHostKeyService = environment.makeSSHHostKeyService()
        self._snapshotStore = StateObject(wrappedValue: environment.makeSnapshotService())
    }
    @State private var discoveryCoordinator: DiscoveryCoordinator? = nil
    @State private var coordinatorStarted = false
    @StateObject private var scanProgress = ScanProgress()
    @StateObject private var appSettings = AppSettings()
    @State private var isBonjourRunning = false
    @State private var isScanRunning = false
    @State private var scanMonitorTask: Task<Void, Never>? = nil
    @State private var portScannerStarted = false
    @State private var sshHostKeyStarted = false
    @State private var httpFingerprintStarted = false
    @State private var showSettingsFromMenu = false

    private let defaultPingConfig = PingConfig(host: "placeholder",
                                               count: 2,
                                               interval: 1.0,
                                               timeoutPerPing: 1.0)
    private let defaultMaxHosts = 254

    var body: some Scene {
        WindowGroup {
            ContentView(store: snapshotStore,
                        progress: scanProgress,
                        settings: appSettings,
                        isBonjourRunning: $isBonjourRunning,
                        isScanRunning: $isScanRunning,
                        startBonjour: { startBonjour() },
                        stopBonjour: { stopBonjour() },
                        startScan: { startScan() },
                        stopScan: { stopScan() },
                        saveSnapshot: { snapshotStore.saveSnapshotNow() },
                        showSettingsFromMenu: $showSettingsFromMenu)
                .preferredColorScheme(.dark)
                .onAppear { startDiscoveryIfNeeded() }
                .environmentObject(appEnvironment)
        }

        #if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Settings...") {
                    showSettingsFromMenu = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }



    private func startDiscoveryIfNeeded() {
        guard !coordinatorStarted else {
            Task { await updateCoordinatorState() }
            startScanMonitor()
            return
        }
        coordinatorStarted = true

#if os(macOS)
        let pingService: PingService = SimplePingKitService()
#else
        let pingService: PingService = SimplePingKitService()
#endif
        let orchestrator = PingOrchestrator(pingService: pingService, mutationBus: appEnvironment.deviceMutationBus, maxConcurrent: 32, progress: scanProgress)
        let providers: [DiscoveryProvider] = [BonjourDiscoveryProvider()]
        let arpService = ARPService()
        let coordinator = DiscoveryCoordinator(store: snapshotStore, pingOrchestrator: orchestrator, mutationBus: appEnvironment.deviceMutationBus, providers: providers, arpService: arpService)
        discoveryCoordinator = coordinator
        if !portScannerStarted {
            portScannerStarted = true
            Task { await portScanService.start() }
        }
        if !sshHostKeyStarted {
            sshHostKeyStarted = true
            sshHostKeyService.start()
        }
        if !httpFingerprintStarted {
            httpFingerprintStarted = true
            httpFingerprintService.start()
            httpFingerprintService.rescan(devices: snapshotStore.devices, force: false)
        }
        let maxHosts = defaultMaxHosts
        Task {
            await coordinator.startBonjour()
            // Auto Bonjour start is coordinated inside DiscoveryCoordinator based on platform sequencing.
#if os(macOS)
            await coordinator.startARPOnly(maxAutoEnumeratedHosts: maxHosts)
#else
            await coordinator.startScan(pingHosts: [],
                                        pingConfig: defaultPingConfig,
                                        mdnsWarmupSeconds: 1.0,
                                        autoEnumerateIfEmpty: true,
                                        maxAutoEnumeratedHosts: maxHosts)
#endif
            await updateCoordinatorState()
            startScanMonitor()
            let devices = await MainActor.run { snapshotStore.devices }
            await portScanService.rescan(devices: devices)
            await MainActor.run { httpFingerprintService.rescan(devices: devices, force: true) }
            await MainActor.run { sshHostKeyService.rescan(devices: devices, force: true) }
        }
    }

    private func startBonjour() {
        guard let coordinator = discoveryCoordinator else { return }
        Task {
            await coordinator.startBonjour()
            await updateCoordinatorState()
        }
    }

    private func stopBonjour() {
        guard let coordinator = discoveryCoordinator else { return }
        Task {
            await coordinator.stopBonjour()
            await updateCoordinatorState()
        }
    }

    private func startScan() {
        guard let coordinator = discoveryCoordinator else { return }
        Task {
            await coordinator.stopScan()
            await coordinator.stopBonjour()
#if os(macOS)
            await coordinator.startDiscoveryPipeline(maxAutoEnumeratedHosts: defaultMaxHosts)
            let devices = await MainActor.run { snapshotStore.devices }
            await portScanService.rescan(devices: devices)
            await MainActor.run { httpFingerprintService.rescan(devices: devices, force: true) }
#else
            await coordinator.startBonjour()
            await coordinator.startDiscoveryPipeline(pingHosts: [],
                                                      pingConfig: defaultPingConfig,
                                                      mdnsWarmupSeconds: 0.5,
                                                      autoEnumerateIfEmpty: true,
                                                      maxAutoEnumeratedHosts: defaultMaxHosts)
            let devices = await MainActor.run { snapshotStore.devices }
            await portScanService.rescan(devices: devices)
            await MainActor.run { httpFingerprintService.rescan(devices: devices, force: true) }
            await MainActor.run { sshHostKeyService.rescan(devices: devices, force: true) }
#endif
            await updateCoordinatorState()
            startScanMonitor()
        }
    }

    private func stopScan() {
        guard let coordinator = discoveryCoordinator else { return }
        Task {
            await coordinator.stopScan()
            await updateCoordinatorState()
            cancelScanMonitor()
        }
    }

    private func restartDiscovery() {
        Task { @MainActor in
            if let coordinator = discoveryCoordinator {
                await coordinator.stopScan()
                await coordinator.stopBonjour()
            }
            cancelScanMonitor()
            discoveryCoordinator = nil
            coordinatorStarted = false
            portScannerStarted = false
            sshHostKeyStarted = false
            isBonjourRunning = false
            isScanRunning = false
            await Task.yield()
            await portScanService.stop()
            sshHostKeyService.stop()
            startDiscoveryIfNeeded()
        }
    }

    private func updateCoordinatorState() async {
        guard let coordinator = discoveryCoordinator else {
            isBonjourRunning = false
            isScanRunning = false
            return
        }
        let state = await coordinator.currentState()
        await MainActor.run {
            isBonjourRunning = state.bonjour
            isScanRunning = state.scanning
        }
    }

    private func startScanMonitor() {
        cancelScanMonitor()
        guard let coordinator = discoveryCoordinator else { return }
        let coordinatorRef = coordinator
        scanMonitorTask = Task { [weak coordinatorRef] in
            guard let coordinator = coordinatorRef else { return }
            while true {
                let state = await coordinator.currentState()
                await MainActor.run {
                    isBonjourRunning = state.bonjour
                    isScanRunning = state.scanning
                }
                if !state.scanning { break }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await MainActor.run { scanMonitorTask = nil }
        }
    }

    private func cancelScanMonitor() {
        scanMonitorTask?.cancel()
        scanMonitorTask = nil
    }
}
