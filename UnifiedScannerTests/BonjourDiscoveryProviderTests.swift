import XCTest
@testable import UnifiedScanner

@MainActor final class BonjourDiscoveryProviderTests: XCTestCase {
    func testSimulatedServicesEmitDevices() async {
        let sims: [BonjourDiscoveryProvider.SimulatedService] = [
            .init(type: "_ssh._tcp", name: "pi", port: 22, hostname: "pi.local", ip: "192.168.1.20"),
            .init(type: "_rfb._tcp", name: "vncbox", port: 5900, hostname: "vncbox.local", ip: "192.168.1.30")
        ]
        let provider = BonjourDiscoveryProvider(simulated: sims)
        let bus = await MainActor.run { DeviceMutationBus.shared }
        let stream = provider.start(mutationBus: bus)
        var collected: [DeviceChange] = []
        for await m in stream {
            if case .change(let change) = m {
                collected.append(change)
            }
        }
        let devices = collected.map { $0.after }
        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices.contains(where: { $0.hostname == "pi.local" && $0.services.first?.type == .ssh }))
        XCTAssertTrue(devices.contains(where: { $0.hostname == "vncbox.local" && $0.services.first?.type == .vnc }))
    }
}
