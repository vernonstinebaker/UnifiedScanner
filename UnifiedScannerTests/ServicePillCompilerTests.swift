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
}
