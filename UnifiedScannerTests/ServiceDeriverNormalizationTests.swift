import XCTest
@testable import UnifiedScanner

final class ServiceDeriverNormalizationTests: XCTestCase {
    func testAdditionalRegtypesNormalization() {
        let samples: [(String, String)] = [
            ("_rfb._tcp", "VNC"),
            ("_sftp-ssh._tcp", "SFTP/SSH"),
            ("_afpovertcp._tcp", "AFP File Sharing"),
            ("_workstation._tcp", "Workstation"),
            ("_device-info._tcp", "Device Info"),
            ("_companion-link._tcp", "Companion Link"),
            ("_remotepairing._tcp", "Remote Pairing"),
            ("_touch-able._tcp", "Touch Able"),
            ("_sleep-proxy._udp", "Sleep Proxy"),
            ("_apple-mobdev2._tcp", "Apple Dev")
        ]
        for (raw, expected) in samples {
            let svc = ServiceDeriver.makeService(fromRaw: raw, port: nil)
            XCTAssertEqual(svc.name, expected, "Expected \(raw) to map to \(expected) got \(svc.name)")
        }
    }
}
