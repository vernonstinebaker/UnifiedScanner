import XCTest
@testable import UnifiedScanner

final class ServicePillCompilerTests: XCTestCase {
    func testAggregatesByLabelAndCounts() {
        let services = [
            NetworkService(name: "AirPlay", type: .airplay, rawType: "_airplay._tcp", port: 7000, isStandardPort: true),
            NetworkService(name: "AirPlay", type: .airplay, rawType: "_airplay._tcp", port: 7000, isStandardPort: true),
            NetworkService(name: "HTTP", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true)
        ]

        let result = ServicePillCompiler.compile(services: services)
        let airplayPill = result.pills.first { $0.type == .airplay }
        XCTAssertEqual(airplayPill?.label, "AirPlay ×2")
        XCTAssertEqual(result.pills.count, 2)
    }

    func testAddsOverflowPillWhenAboveLimit() {
        let services = [
            NetworkService(name: "SSH", type: .ssh, rawType: "_ssh._tcp", port: 22, isStandardPort: true),
            NetworkService(name: "AirPlay", type: .airplay, rawType: "_airplay._tcp", port: 7000, isStandardPort: true),
            NetworkService(name: "HTTP", type: .http, rawType: "_http._tcp", port: 8080, isStandardPort: false)
        ]

        let result = ServicePillCompiler.compile(services: services, maxVisible: 1)
        XCTAssertEqual(result.pills.count, 2)
        XCTAssertTrue(result.pills.last?.isOverflow == true)
        XCTAssertEqual(result.pills.last?.label, "+2")
    }

    func testNonStandardPortAppendsPort() {
        let services = [NetworkService(name: "HTTP", type: .http, rawType: "_http._tcp", port: 8080, isStandardPort: false)]
        let result = ServicePillCompiler.compile(services: services)
        XCTAssertEqual(result.pills.count, 1)
        XCTAssertEqual(result.pills.first?.label, "HTTP :8080")
    }

    func testGroupingByLabel() {
        let services = [
            NetworkService(name: "AirPlay", type: .airplay, port: 7000, isStandardPort: true),
            NetworkService(name: "AirPlay", type: .airplay, port: 7000, isStandardPort: true), // same label
            NetworkService(name: "HTTP", type: .http, port: 80, isStandardPort: true),
            NetworkService(name: "HTTPS", type: .https, port: 443, isStandardPort: true)
        ]
        let (pills, overflow) = ServicePillCompiler.compile(services: services)
        XCTAssertEqual(pills.count, 3)
        XCTAssertEqual(overflow, 0)
        let airplayPill = pills.first { $0.type == .airplay }
        XCTAssertEqual(airplayPill?.label, "AirPlay ×2")
    }

    func testSortingByTypeThenLabel() {
        let services = [
            NetworkService(name: "Zebra", type: .http, port: nil, isStandardPort: false),
            NetworkService(name: "Apple", type: .http, port: nil, isStandardPort: false),
            NetworkService(name: "Banana", type: .ssh, port: nil, isStandardPort: false)
        ]
        let (pills, _) = ServicePillCompiler.compile(services: services)
        let labels = pills.map { $0.label }
        XCTAssertEqual(labels, ["Apple", "Zebra", "Banana"])
    }

    func testMaxVisibleZeroShowsOverflowOnly() {
        let services = [
            NetworkService(name: "Service1", type: .http, port: nil, isStandardPort: false),
            NetworkService(name: "Service2", type: .ssh, port: nil, isStandardPort: false)
        ]
        let (pills, overflow) = ServicePillCompiler.compile(services: services, maxVisible: 0)
        XCTAssertEqual(pills.count, 1)
        XCTAssertTrue(pills.first?.isOverflow ?? false)
        XCTAssertEqual(pills.first?.label, "+2")
        XCTAssertEqual(overflow, 2)
    }

    func testEmptyServices() {
        let (pills, overflow) = ServicePillCompiler.compile(services: [])
        XCTAssertTrue(pills.isEmpty)
        XCTAssertEqual(overflow, 0)
    }

    func testOverflowCalculation() {
        let services = Array(repeating: NetworkService(name: "Test", type: .other, port: nil, isStandardPort: false), count: 5)
        let (pills, overflow) = ServicePillCompiler.compile(services: services, maxVisible: 3)
        XCTAssertEqual(pills.count, 4)
        XCTAssertEqual(overflow, 2)
        XCTAssertEqual(pills.last?.label, "+2")
    }

    func testDisplayLabelEmptyNameUsesType() {
        let service = NetworkService(name: "", type: .http, rawType: nil, port: nil, isStandardPort: false)
        let label = ServicePillCompiler.displayLabel(for: service)
        XCTAssertEqual(label, "HTTP")
    }

    func testDisplayLabelTrimsWhitespace() {
        let service = NetworkService(name: " HTTP ", type: .http, rawType: nil, port: nil, isStandardPort: false)
        let label = ServicePillCompiler.displayLabel(for: service)
        XCTAssertEqual(label, "HTTP")
    }

    func testDisplayLabelStandardPortNoAppend() {
        let service = NetworkService(name: "HTTP", type: .http, rawType: nil, port: 80, isStandardPort: true)
        let label = ServicePillCompiler.displayLabel(for: service)
        XCTAssertEqual(label, "HTTP")
    }

    func testDisplayLabelAlreadyHasPort() {
        let service = NetworkService(name: "HTTP:8080", type: .http, rawType: nil, port: 8080, isStandardPort: false)
        let label = ServicePillCompiler.displayLabel(for: service)
        XCTAssertEqual(label, "HTTP:8080")
    }

    func testServiceTypeMatchesDefaultPort() {
        XCTAssertTrue(NetworkService.ServiceType.http.matchesDefaultPort(80))
        XCTAssertFalse(NetworkService.ServiceType.http.matchesDefaultPort(8080))
        XCTAssertTrue(NetworkService.ServiceType.smb.matchesDefaultPort(139))
        XCTAssertTrue(NetworkService.ServiceType.smb.matchesDefaultPort(445))
        XCTAssertTrue(NetworkService.ServiceType.airplay.matchesDefaultPort(7000))
        XCTAssertFalse(NetworkService.ServiceType.other.matchesDefaultPort(80))
    }

    func testPillIdentifiableAndHashable() {
        let pill1 = ServicePill(id: "1", label: "Test", type: .http, isOverflow: false)
        let pill2 = ServicePill(id: "1", label: "Test", type: .http, isOverflow: false)
        let pill3 = ServicePill(id: "2", label: "Other", type: .ssh, isOverflow: false)
        XCTAssertEqual(pill1, pill2)
        XCTAssertNotEqual(pill1, pill3)
        let set: Set<ServicePill> = [pill1, pill2, pill3]
        XCTAssertEqual(set.count, 2)
    }
}
