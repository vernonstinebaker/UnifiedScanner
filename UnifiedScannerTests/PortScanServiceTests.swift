import XCTest
@testable import UnifiedScanner

final class PortScanServiceTests: XCTestCase {
    func testPortScanEmitsOpenPortMutation() async {
        let bus = await MainActor.run { DeviceMutationBus() }
        let prober = StubPortProber(results: [22: .open, 80: .closed, 443: .closed])
        let service = PortScanService(mutationBus: bus,
                                      ports: [22, 80, 443],
                                      timeout: 0.01,
                                      rescanInterval: 0,
                                      prober: prober)

        await service.start()

        let mutationStream = await MainActor.run { bus.mutationStream(includeBuffered: false) }
        let expectation = expectation(description: "Port scan mutation received")
        var capturedChange: DeviceChange?

        let collectTask = Task {
            for await mutation in mutationStream {
                if case .change(let change) = mutation, change.source == .portScan {
                    capturedChange = change
                    expectation.fulfill()
                    break
                }
            }
        }

        let device = Device(primaryIP: "192.168.1.50",
                            ips: ["192.168.1.50"],
                            hostname: "test-device",
                            discoverySources: [.mdns])
        let change = DeviceChange(before: nil,
                                  after: device,
                                  changed: Set(DeviceField.allCases),
                                  source: .mdns)
        await MainActor.run {
            bus.emit(.change(change))
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        collectTask.cancel()

        guard let portChange = capturedChange else {
            XCTFail("Expected port scan change mutation")
            return
        }

        XCTAssertEqual(portChange.source, .portScan)
        XCTAssertTrue(portChange.changed.contains(.openPorts))
        XCTAssertTrue(portChange.changed.contains(.services))
        XCTAssertTrue(portChange.after.openPorts.contains(where: { $0.number == 22 && $0.status == .open }))
        XCTAssertTrue(portChange.after.services.contains(where: { $0.port == 22 && $0.type == .ssh }))
    }

    func testPortScanUpdatesExistingDeviceUnionsDiscoverySources() async {
        let bus = await MainActor.run { DeviceMutationBus() }
        let prober = StubPortProber(results: [22: .open])
        let service = PortScanService(mutationBus: bus,
                                      ports: [22],
                                      timeout: 0.01,
                                      rescanInterval: 0,
                                      prober: prober)

        await service.start()

        let mutationStream = await MainActor.run { bus.mutationStream(includeBuffered: false) }
        let expectation = expectation(description: "Port scan update mutation received")
        var capturedChange: DeviceChange?

        let collectTask = Task {
            for await mutation in mutationStream {
                if case .change(let change) = mutation, change.source == .portScan {
                    capturedChange = change
                    expectation.fulfill()
                    break
                }
            }
        }

        // First, emit an existing device with mdns source
        let existingDevice = Device(primaryIP: "192.168.1.50",
                                    ips: ["192.168.1.50"],
                                    hostname: "test-device",
                                    discoverySources: [.mdns])
        let initialChange = DeviceChange(before: nil,
                                         after: existingDevice,
                                         changed: Set(DeviceField.allCases),
                                         source: .mdns)
        await MainActor.run {
            bus.emit(.change(initialChange))
        }

        // Then emit an update for the same device (simulating another source adding info)
        let updatedDevice = existingDevice.withDiscoverySources([.arp]) // but port scan should union
        let updateChange = DeviceChange(before: existingDevice,
                                        after: updatedDevice,
                                        changed: [.discoverySources],
                                        source: .arp)
        await MainActor.run {
            bus.emit(.change(updateChange))
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        collectTask.cancel()

        guard let portChange = capturedChange else {
            XCTFail("Expected port scan change mutation")
            return
        }

        XCTAssertEqual(portChange.source, .portScan)
        XCTAssertTrue(portChange.changed.contains(.openPorts))
        XCTAssertTrue(portChange.changed.contains(.services))
        XCTAssertTrue(portChange.changed.contains(.discoverySources))
        XCTAssertTrue(portChange.after.openPorts.contains(where: { $0.number == 22 && $0.status == .open }))
        XCTAssertTrue(portChange.after.services.contains(where: { $0.port == 22 && $0.type == .ssh }))
        // Check union: should have mdns, portScan
        XCTAssertTrue(portChange.after.discoverySources.contains(.mdns))
        XCTAssertFalse(portChange.after.discoverySources.contains(.arp))
        XCTAssertTrue(portChange.after.discoverySources.contains(.portScan))
        XCTAssertEqual(portChange.after.discoverySources.count, 2)
    }

private struct StubPortProber: PortProbing {
    let results: [UInt16: PortProbeResult]
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortProbeResult {
        results[port] ?? .closed
    }
}
}

@MainActor
final class SSHHostKeyServiceTests: XCTestCase {
    func testSSHHostKeyServiceEmitsFingerprint() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let mockCollector = MockCollector(result: ["ssh.hostkey.rsa.sha256": "ABC="])
        let service = SSHHostKeyService(mutationBus: bus, collector: mockCollector, cooldown: 0, timeout: 0.1)

        let stream = bus.mutationStream(includeBuffered: false)
        let expectation = expectation(description: "Host key fingerprint emitted")
        var capturedChange: DeviceChange?

        let collectTask = Task {
            for await mutation in stream {
                if case .change(let change) = mutation, change.source == .portScan {
                    if let fingerprints = change.after.fingerprints,
                       fingerprints["ssh.hostkey.rsa.sha256"] == "ABC=" {
                        capturedChange = change
                        expectation.fulfill()
                        break
                    }
                }
            }
        }

        let device = Device(primaryIP: "router.local",
                            ips: ["router.local"],
                            hostname: "router.local",
                            discoverySources: [.portScan],
                            services: [NetworkService(name: "SSH", type: .ssh, rawType: "_ssh._tcp", port: 22, isStandardPort: true)],
                            openPorts: [Port(number: 22, transport: "tcp", serviceName: "ssh", description: "SSH", status: .open, lastSeenOpen: Date())])

        service.rescan(devices: [device], force: true)

        await fulfillment(of: [expectation], timeout: 1.0)
        collectTask.cancel()

        XCTAssertNotNil(capturedChange)
    }

    private struct MockCollector: SSHHostKeyCollecting {
        let result: [String: String]
        func collect(target: SSHFingerprintTarget, timeout: TimeInterval) async -> [String: String] {
            _ = target
            _ = timeout
            return result
        }
    }
}
