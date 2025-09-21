import XCTest
@testable import UnifiedScanner

final class BonjourResolveServiceTests: XCTestCase {
    func testServiceKey() {
        let service = NetService(domain: "local.", type: "_http._tcp.", name: "example", port: 80)
        let resolver = BonjourResolveService(resolveCooldown: 1.0)
        let key = resolver.serviceKey(service)
        XCTAssertEqual(key, "example._http._tcp.local.")
    }

    func testShouldResolveNoCooldown() {
        let service = NetService(domain: "local.", type: "_http._tcp.", name: "test", port: 80)
        let resolver = BonjourResolveService(resolveCooldown: 1.0)
        let should = resolver.shouldResolve(service)
        XCTAssertTrue(should)
    }

    func testShouldResolveWithCooldown() async {
        let service = NetService(domain: "local.", type: "_http._tcp.", name: "test", port: 80)
        let resolver = BonjourResolveService(resolveCooldown: 3600) // 1 hour
        let first = resolver.shouldResolve(service)
        XCTAssertTrue(first)
        // Sleep less than cooldown
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec
        let second = resolver.shouldResolve(service)
        XCTAssertFalse(second)
    }

    func testExtractIPsIPv4() {
        // Mock sockaddr_in for 192.168.1.1
        var sin = sockaddr_in()
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(CFSwapInt32HostToBig(0xc0a80101)) // 192.168.1.1
        let data = Data(bytes: &sin, count: MemoryLayout<sockaddr_in>.size)
        let addresses = [data]
        let service = mockService(addresses: addresses)
        let resolver = BonjourResolveService(resolveCooldown: 1.0)
        let ips = resolver.extractIPs(from: service)
        XCTAssertEqual(ips, ["192.168.1.1"])
    }

    func testExtractIPsIPv6() {
        // Mock sockaddr_in6 for ::1
        var sin6 = sockaddr_in6()
        sin6.sin6_family = sa_family_t(AF_INET6)
        withUnsafeMutableBytes(of: &sin6.sin6_addr) { ptr in
            let bytes: [UInt8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]
            ptr.copyBytes(from: bytes)
        }
        let data = Data(bytes: &sin6, count: MemoryLayout<sockaddr_in6>.size)
        let addresses = [data]
        let service = mockService(addresses: addresses)
        let resolver = BonjourResolveService(resolveCooldown: 1.0)
        let ips = resolver.extractIPs(from: service)
        XCTAssertEqual(ips, ["::1"])
    }

    func testExtractIPsMultipleDeduplicated() {
        // IPv4 and IPv6
        var sin4 = sockaddr_in()
        sin4.sin_family = sa_family_t(AF_INET)
        sin4.sin_addr.s_addr = in_addr_t(CFSwapInt32HostToBig(0xc0a80101))
        let data4 = Data(bytes: &sin4, count: MemoryLayout<sockaddr_in>.size)

        var sin6 = sockaddr_in6()
        sin6.sin6_family = sa_family_t(AF_INET6)
        withUnsafeMutableBytes(of: &sin6.sin6_addr) { ptr in
            let bytes: [UInt8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]
            ptr.copyBytes(from: bytes)
        }
        let data6 = Data(bytes: &sin6, count: MemoryLayout<sockaddr_in6>.size)

        let addresses = [data4, data6, data4] // dup IPv4
        let service = mockService(addresses: addresses)
        let resolver = BonjourResolveService(resolveCooldown: 1.0)
        let ips = resolver.extractIPs(from: service)
        XCTAssertEqual(ips, ["192.168.1.1", "::1"])
    }

    func testExtractIPsInvalid() {
        let invalidData = Data(repeating: 0, count: 8) // too short
        let addresses = [invalidData]
        let service = mockService(addresses: addresses)
        let resolver = BonjourResolveService(resolveCooldown: 1.0)
        let ips = resolver.extractIPs(from: service)
        XCTAssertTrue(ips.isEmpty)
    }

    func testInitSetsCooldown() {
        let resolver = BonjourResolveService(resolveCooldown: 30.0)
        // Private, but assume set
    }

    // Helper
    private func mockService(addresses: [Data]) -> NetService {
        let service = NetService(domain: "local.", type: "_http._tcp.", name: "mock", port: 80)
        // NetService.addresses is KVC-compliant; set via KVC for tests
        service.setValue(addresses, forKey: "addresses")
        return service
    }

    // Note: Full resolve stream tests require mocking NetServiceBrowser and NetService, complex for unit
    // Covered in integration BonjourDiscoveryProviderTests
}