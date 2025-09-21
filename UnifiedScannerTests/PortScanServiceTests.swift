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
        XCTAssertTrue(portChange.after.discoverySources.contains(.portScan))
    }
}

private struct StubPortProber: PortProbing {
    let results: [UInt16: PortProbeResult]
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortProbeResult {
        results[port] ?? .closed
    }
}
