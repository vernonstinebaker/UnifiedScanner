import XCTest
@testable import UnifiedScanner

@MainActor final class SnapshotServiceOfflineTests: XCTestCase {
    func testDeviceMarkedOfflineAfterGraceInterval() async {
        let store = SnapshotService(persistence: EphemeralPersistence(), offlineCheckInterval: 0.05, onlineGraceInterval: 0.1)
        var d = Device.mockMac
        await store.upsert(d)
        // Ensure device starts considered online (override nil + recentlySeen true)
        XCTAssertNil(store.devices.first?.isOnlineOverride)
        // Sleep past grace interval
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s > 0.1 grace
        // Allow at least one heartbeat cycle after grace (0.05s)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let device = store.devices.first!
        XCTAssertEqual(device.isOnlineOverride, false, "Expected offline override after exceeding grace interval")
    }
}
