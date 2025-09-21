//
//  UnifiedScannerApp.swift
//  UnifiedScanner
//
//  Created by Vernon Stinebaker on 9/18/25.
//

import SwiftUI

@main
struct UnifiedScannerApp: App {
    init() {
        ClassificationService.setOUILookupProvider(OUILookupService.shared)
    }

    private let mutationBus = DeviceMutationBus.shared
    @StateObject private var snapshotStore = SnapshotService()
    @State private var discoveryCoordinator: DiscoveryCoordinator? = nil
    @State private var coordinatorStarted = false
    @StateObject private var scanProgress = ScanProgress()
    @StateObject private var appSettings = AppSettings()
    @State private var isBonjourRunning = false
    @State private var isScanRunning = false
    @State private var scanMonitorTask: Task<Void, Never>? = nil

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
                    saveSnapshot: { snapshotStore.saveSnapshotNow() })
            .preferredColorScheme(.dark)
            .onAppear { startDiscoveryIfNeeded() }
    }
#if os(macOS)
    .commands {
        CommandGroup(replacing: .newItem) {
            Button("Clear KV Store") { clearKVStore() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
#endif
}

    private func clearKVStore() {
        // Clear both NSUbiquitousKeyValueStore and UserDefaults backing store key
        let key = "unifiedscanner:devices:v1"
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
        UserDefaults.standard.removeObject(forKey: key)
        snapshotStore.removeAll()
        Task { await scanProgress.reset() }
    }

    private func startDiscoveryIfNeeded() {
        guard !coordinatorStarted else {
            Task { await updateCoordinatorState() }
            startScanMonitor()
            return
        }
        coordinatorStarted = true

#if os(macOS)
        let pingService: PingService = NoopPingService()
#else
        let pingService: PingService = SimplePingKitService()
#endif
        let orchestrator = PingOrchestrator(pingService: pingService, mutationBus: DeviceMutationBus.shared, maxConcurrent: 32, progress: scanProgress)
        let providers: [DiscoveryProvider] = [BonjourDiscoveryProvider()]
        let arpService = ARPService()
        let coordinator = DiscoveryCoordinator(store: snapshotStore, pingOrchestrator: orchestrator, mutationBus: DeviceMutationBus.shared, providers: providers, arpService: arpService)
        discoveryCoordinator = coordinator
        Task {
            await coordinator.startBonjour()
            await coordinator.startScan(pingHosts: [],
                                        pingConfig: defaultPingConfig,
                                        mdnsWarmupSeconds: 1.0,
                                        autoEnumerateIfEmpty: true,
                                        maxAutoEnumeratedHosts: defaultMaxHosts)
            await updateCoordinatorState()
            startScanMonitor()
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
            await coordinator.startScan(pingHosts: [],
                                        pingConfig: defaultPingConfig,
                                        mdnsWarmupSeconds: 0.5,
                                        autoEnumerateIfEmpty: true,
                                        maxAutoEnumeratedHosts: defaultMaxHosts)
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
