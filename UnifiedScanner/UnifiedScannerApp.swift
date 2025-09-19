//
//  UnifiedScannerApp.swift
//  UnifiedScanner
//
//  Created by Vernon Stinebaker on 9/18/25.
//

import SwiftUI

@main
struct UnifiedScannerApp: App {
    @StateObject private var snapshotStore = DeviceSnapshotStore()
    @State private var discoveryCoordinator: DiscoveryCoordinator? = nil
    @State private var coordinatorStarted = false
    @StateObject private var scanProgress = ScanProgress()

    var body: some Scene {
        WindowGroup {
            ContentView(store: snapshotStore, progress: scanProgress)
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
        scanProgress.reset()
    }

    private func startDiscoveryIfNeeded() {
        guard !coordinatorStarted else { return }
        coordinatorStarted = true

        let pinger = PlatformPingerFactory.make()
        let orchestrator = PingOrchestrator(pinger: pinger, store: snapshotStore, maxConcurrent: 32, progress: scanProgress)
        let providers: [DiscoveryProvider] = [] // mDNS discovery disabled until real provider implemented
        let arpReader = ARPTableReader()
        let coordinator = DiscoveryCoordinator(store: snapshotStore, pingOrchestrator: orchestrator, providers: providers, arpReader: arpReader)
        discoveryCoordinator = coordinator
        Task {
            await coordinator.start(pingHosts: [],
                                    pingConfig: PingConfig(host: "placeholder", count: 2, interval: 1.0, timeoutPerPing: 1.0),
                                    mdnsWarmupSeconds: 1.0,
                                    autoEnumerateIfEmpty: true,
                                     maxAutoEnumeratedHosts: 254)
        }
    }
}
