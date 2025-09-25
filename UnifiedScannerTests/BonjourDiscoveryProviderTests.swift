import XCTest
@testable import UnifiedScanner

final class BonjourDiscoveryProviderTests: XCTestCase {
    func testSimulatedServicesEmitDevices() async {
        let sims: [BonjourDiscoveryProvider.SimulatedService] = [
            .init(type: "_ssh._tcp", name: "pi", port: 22, hostname: "pi.local", ip: "192.168.1.20"),
            .init(type: "_rfb._tcp", name: "vncbox", port: 5900, hostname: "vncbox.local", ip: "192.168.1.30")
        ]
        let provider = BonjourDiscoveryProvider(simulated: sims)
        let bus = await MainActor.run { DeviceMutationBus() }
        let stream = provider.start(mutationBus: bus)
        var collected: [DeviceChange] = []
        for await m in stream {
            if case .change(let change) = m {
                collected.append(change)
            }
        }
        let devices = collected.map { $0.after }.sorted { ($0.hostname ?? "") < ($1.hostname ?? "") }
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].hostname, "pi.local")
        XCTAssertEqual(devices[0].services.first?.type, .ssh)
        XCTAssertEqual(devices[1].hostname, "vncbox.local")
        XCTAssertEqual(devices[1].services.first?.type, .vnc)
        provider.stop()
    }
}
