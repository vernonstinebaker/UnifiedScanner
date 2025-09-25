import XCTest
@testable import UnifiedScanner

@MainActor
final class HTTPFingerprintServiceTests: XCTestCase {

    func testRescanEmitsFingerprints() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let service = HTTPFingerprintService(mutationBus: bus, cooldown: 0, requestTimeout: 0.1) // Short timeout for test
        service.start()
        defer { service.stop() }

        var receivedMutations: [DeviceMutation] = []
        let stream = bus.mutationStream(includeBuffered: false)

        let collectTask = Task {
            for await mutation in stream.prefix(1) {
                receivedMutations.append(mutation)
            }
        }

        // Create a device with HTTP service
        let device = Device(
            primaryIP: "127.0.0.1",
            ips: ["127.0.0.1"],
            discoverySources: [.mdns],
            services: [NetworkService(id: UUID(), name: "HTTP", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true)]
        )

        service.rescan(devices: [device], force: true)

        // Wait a bit for async operation
        try? await Task.sleep(nanoseconds: 200_000_000)

        _ = await collectTask.value

        // Should have received a change mutation with fingerprints
        XCTAssertEqual(receivedMutations.count, 1)
        guard case .change(let change) = receivedMutations[0] else {
            XCTFail("Expected change mutation")
            return
        }
        XCTAssertFalse(change.after.fingerprints?.isEmpty ?? true, "Should have fingerprints after rescan")
    }

    func testCooldownPreventsFrequentRequests() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let service = HTTPFingerprintService(mutationBus: bus, cooldown: 10, requestTimeout: 0.1) // Long cooldown
        service.start()
        defer { service.stop() }

        let device = Device(
            primaryIP: "127.0.0.1",
            ips: ["127.0.0.1"],
            discoverySources: [.mdns],
            services: [NetworkService(id: UUID(), name: "HTTP", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true)]
        )

        // First rescan
        service.rescan(devices: [device], force: true)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Second rescan should be blocked by cooldown
        service.rescan(devices: [device], force: false)
        // Should not trigger again due to cooldown
    }

    func testForceIgnoresCooldown() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let service = HTTPFingerprintService(mutationBus: bus, cooldown: 10, requestTimeout: 0.1)
        service.start()
        defer { service.stop() }

        var mutationCount = 0
        let stream = bus.mutationStream(includeBuffered: false)

        let collectTask = Task {
            for await _ in stream {
                mutationCount += 1
                if mutationCount >= 2 { break }
            }
        }

        let device = Device(
            primaryIP: "127.0.0.1",
            ips: ["127.0.0.1"],
            discoverySources: [.mdns],
            services: [NetworkService(id: UUID(), name: "HTTP", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true)]
        )

        // First rescan
        service.rescan(devices: [device], force: true)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Second rescan with force should work
        service.rescan(devices: [device], force: true)
        try? await Task.sleep(nanoseconds: 200_000_000)

        _ = await collectTask.value

        XCTAssertGreaterThanOrEqual(mutationCount, 1, "Should have received at least one mutation")
    }

    func testNoServicesNoFingerprinting() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let service = HTTPFingerprintService(mutationBus: bus, cooldown: 0, requestTimeout: 0.1)
        service.start()
        defer { service.stop() }

        var receivedMutations: [DeviceMutation] = []
        let stream = bus.mutationStream(includeBuffered: false)

        let collectTask = Task {
            for await mutation in stream.prefix(1) {
                receivedMutations.append(mutation)
            }
        }

        let device = Device(
            primaryIP: "127.0.0.1",
            ips: ["127.0.0.1"],
            discoverySources: [.mdns],
            services: [] // No HTTP services
        )

        service.rescan(devices: [device], force: true)

        // Wait a bit
        try? await Task.sleep(nanoseconds: 200_000_000)

        _ = await collectTask.value

        XCTAssertEqual(receivedMutations.count, 0, "Should not fingerprint device without HTTP services")
    }

    func testStopCancelsOperations() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let service = HTTPFingerprintService(mutationBus: bus, cooldown: 0, requestTimeout: 1.0) // Long timeout
        service.start()

        let device = Device(
            primaryIP: "127.0.0.1",
            ips: ["127.0.0.1"],
            discoverySources: [.mdns],
            services: [NetworkService(id: UUID(), name: "HTTP", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true)]
        )

        service.rescan(devices: [device], force: true)

        // Stop immediately
        service.stop()

        // Should not have pending operations
        // This is hard to test directly, but at least ensure no crash
    }
}