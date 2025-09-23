import XCTest
@testable import UnifiedScanner

final class AppleTVAuthoritativeFingerprintTests: XCTestCase {
    func testFingerprintBeatsHostnameHeuristic() async {
        // Hostname suggests Apple TV, fingerprint also present.
        var d = Device(primaryIP: "192.168.1.222",
                       hostname: "Apple-TV.local",
                       vendor: "Apple",
                       discoverySources: [.mdns],
                       services: [ServiceDeriver.makeService(fromRaw: "_airplay._tcp", port: 7000)],
                       openPorts: [],
                       fingerprints: ["model": "AppleTV11,1"]) // Apple TV 4K (3rd gen) example
        d.classification = await ClassificationService.classify(device: d)
        XCTAssertEqual(d.classification?.formFactor, .tv)
        XCTAssertEqual(d.classification?.confidence, .high)
        XCTAssertTrue(d.classification?.reason.contains("authoritative") == true, "Expected authoritative short-circuit reason, got: \(String(describing: d.classification?.reason))")
        XCTAssertTrue(d.classification?.sources.contains(where: { $0.hasPrefix("fingerprint") }) == true)
    }
}
