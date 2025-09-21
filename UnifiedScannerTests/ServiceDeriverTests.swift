import XCTest
@testable import UnifiedScanner

final class ServiceDeriverTests: XCTestCase {
    func testWellKnownPortsMapping() {
        if let entry = ServiceDeriver.wellKnownPorts[80] { XCTAssertEqual(entry.0, .http); XCTAssertEqual(entry.1, "HTTP") } else { XCTFail("missing entry for 80") }
        if let entry = ServiceDeriver.wellKnownPorts[443] { XCTAssertEqual(entry.0, .https); XCTAssertEqual(entry.1, "HTTPS") } else { XCTFail("missing entry for 443") }
        if let entry = ServiceDeriver.wellKnownPorts[22] { XCTAssertEqual(entry.0, .ssh); XCTAssertEqual(entry.1, "SSH") } else { XCTFail("missing entry for 22") }
        if let entry = ServiceDeriver.wellKnownPorts[53] { XCTAssertEqual(entry.0, .dns); XCTAssertEqual(entry.1, "DNS") } else { XCTFail("missing entry for 53") }
        if let entry = ServiceDeriver.wellKnownPorts[139] { XCTAssertEqual(entry.0, .smb); XCTAssertEqual(entry.1, "SMB") } else { XCTFail("missing entry for 139") }
        if let entry = ServiceDeriver.wellKnownPorts[3689] { XCTAssertEqual(entry.0, .airplayAudio); XCTAssertEqual(entry.1, "DAAP") } else { XCTFail("missing entry for 3689") }

        XCTAssertNil(ServiceDeriver.wellKnownPorts[9999])
    }

    func testNormalizeRawTypeCommon() {
        let tests: [(String, NetworkService.ServiceType, String)] = [
            ("_airplay._tcp", .airplay, "AirPlay"),
            ("_raop._tcp", .airplayAudio, "AirPlay Audio"),
            ("_homekit._tcp", .homekit, "HomeKit"),
            ("_ssh._tcp", .ssh, "SSH"),
            ("_https._tcp", .https, "HTTPS"),
            ("_http._tcp", .http, "HTTP"),
            ("_ipp._tcp", .ipp, "IPP"),
            ("_printer._tcp", .printer, "Printer"),
            ("_spotify._tcp", .spotify, "Spotify"),
            ("_googlecast._tcp", .chromecast, "Chromecast")
        ]
        for (raw, expectedType, expectedName) in tests {
            let (type, name) = ServiceDeriver.normalize(rawType: raw)
            XCTAssertEqual(type, expectedType, "For \(raw)")
            XCTAssertEqual(name, expectedName, "For \(raw)")
        }
    }

    func testNormalizeRawTypeOther() {
        let (type, name) = ServiceDeriver.normalize(rawType: "_unknown._tcp.local")
        XCTAssertEqual(type, .other)
        XCTAssertEqual(name, "unknown")
    }

    func testMakeServiceFromRaw() {
        let svc = ServiceDeriver.makeService(fromRaw: "_airplay._tcp", port: 7000)
        XCTAssertEqual(svc.type, .airplay)
        XCTAssertEqual(svc.name, "AirPlay")
        XCTAssertEqual(svc.rawType, "_airplay._tcp")
        XCTAssertEqual(svc.port, 7000)
        XCTAssertTrue(svc.isStandardPort)

        let otherSvc = ServiceDeriver.makeService(fromRaw: "_custom._tcp", port: 1234)
        XCTAssertEqual(otherSvc.type, .other)
        XCTAssertEqual(otherSvc.name, "custom")
        XCTAssertFalse(otherSvc.isStandardPort)
    }

    func testDisplayServicesDeduplicationExplicit() {
        let svc1 = NetworkService(name: "HTTP Server", type: .http, rawType: nil, port: 80, isStandardPort: true)
        let svc2 = NetworkService(name: "Web", type: .http, rawType: nil, port: 80, isStandardPort: true)
        let services = [svc1, svc2]
        let display = ServiceDeriver.displayServices(services: services, openPorts: [])
        XCTAssertEqual(display.count, 1)
        XCTAssertEqual(display.first?.name, "HTTP Server") // Longer name preferred
    }

    func testDisplayServicesAddsPortDerived() {
        let explicit = NetworkService(name: "SSH", type: .ssh, rawType: nil, port: 22, isStandardPort: true)
        let ports = [Port(number: 80, serviceName: "http", description: "HTTP", status: .open, lastSeenOpen: nil)]
        let display = ServiceDeriver.displayServices(services: [explicit], openPorts: ports)
        XCTAssertEqual(display.count, 2)
        XCTAssertTrue(display.contains { $0.type == .http && $0.name == "HTTP" })
    }

    func testDisplayServicesNoDuplicateFromPort() {
        let explicitHTTP = NetworkService(name: "HTTP", type: .http, rawType: nil, port: 80, isStandardPort: true)
        let ports = [Port(number: 80, serviceName: "http", description: "HTTP", status: .open, lastSeenOpen: nil)]
        let display = ServiceDeriver.displayServices(services: [explicitHTTP], openPorts: ports)
        XCTAssertEqual(display.count, 1)
    }

    func testDisplayServicesSorting() {
        let http = NetworkService(name: "HTTP", type: .http, port: 80, isStandardPort: true)
        let ssh = NetworkService(name: "SSH", type: .ssh, port: 22, isStandardPort: true)
        let other = NetworkService(name: "Custom", type: .other, port: 1234, isStandardPort: false)
        let services = [other, ssh, http]
        let display = ServiceDeriver.displayServices(services: services, openPorts: [])
        let types = display.map { $0.type }
        XCTAssertEqual(types, [.http, .ssh, .other])
    }

    func testDisplayServicesPortSorting() {
        let http80 = NetworkService(name: "HTTP", type: .http, port: 80, isStandardPort: true)
        let http8080 = NetworkService(name: "HTTP Alt", type: .http, port: 8080, isStandardPort: false)
        let display = ServiceDeriver.displayServices(services: [http8080, http80], openPorts: [])
        XCTAssertEqual(display.first?.port, 80)
    }

    func testDisplayServicesNameSortingSameTypePort() {
        let svc1 = NetworkService(name: "Apple", type: .airplay, port: nil, isStandardPort: true)
        let svc2 = NetworkService(name: "Banana", type: .airplay, port: nil, isStandardPort: true)
        let display = ServiceDeriver.displayServices(services: [svc2, svc1], openPorts: [])
        XCTAssertEqual(display.first?.name, "Apple")
    }

    func testServiceTypeSortIndex() {
        XCTAssertEqual(NetworkService.ServiceType.http.sortIndex, 0)
        XCTAssertEqual(NetworkService.ServiceType.https.sortIndex, 1)
        XCTAssertEqual(NetworkService.ServiceType.ssh.sortIndex, 2)
        XCTAssertEqual(NetworkService.ServiceType.other.sortIndex, 16)
    }

    func testClosedPortsIgnored() {
        let closedPort = Port(number: 80, serviceName: "http", description: "HTTP", status: .closed, lastSeenOpen: nil)
        let display = ServiceDeriver.displayServices(services: [], openPorts: [closedPort])
        XCTAssertTrue(display.isEmpty)
    }
}
