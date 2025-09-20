import XCTest
@testable import UnifiedScanner

final class BonjourDiscoveryProviderTests: XCTestCase {
    func testSimulatedServicesEmitDevices() async {
        let sims: [BonjourDiscoveryProvider.SimulatedService] = [
            .init(type: "_ssh._tcp", name: "pi", port: 22, hostname: "pi.local", ip: "192.168.1.20"),
            .init(type: "_rfb._tcp", name: "vncbox", port: 5900, hostname: "vncbox.local", ip: "192.168.1.30")
        ]
        let provider = BonjourDiscoveryProvider(simulated: sims)
        let stream = provider.start()
        var collected: [Device] = []
        for await dev in stream {
            collected.append(dev)
        }
        XCTAssertEqual(collected.count, 2)
        XCTAssertTrue(collected.contains(where: { $0.hostname == "pi.local" && $0.services.first?.type == .ssh }))
        XCTAssertTrue(collected.contains(where: { $0.hostname == "vncbox.local" && $0.services.first?.type == .vnc }))
    }
}
