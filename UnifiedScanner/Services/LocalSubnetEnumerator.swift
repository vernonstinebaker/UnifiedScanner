import Foundation
import Darwin

// MARK: - Host Enumeration Abstraction
@preconcurrency protocol HostEnumerator: Sendable { // not actor-isolated
    func enumerate(maxHosts: Int?) -> [String]
}

/// Utility responsible for deriving a candidate host list for ping discovery when
/// explicit hosts are not provided. Strategy: pick the first active non-loopback
/// IPv4 interface whose name starts with `en` (Wi‑Fi / Ethernet convention on Apple
/// platforms) and expand a /24 (x.y.z.1 ... x.y.z.254) excluding the local host
/// itself plus network (.0) and broadcast (.255). This mirrors (simplified) logic
/// adapted from legacy netscan `BonjourDiscoverer.getLocalSubnetIPs` (reference only).
struct LocalSubnetEnumerator: HostEnumerator {
    // Instance entry point satisfying protocol
    func enumerate(maxHosts: Int? = nil) -> [String] { Self.enumerate(maxHosts: maxHosts) }

    // Original static implementation retained for internal reuse / tests
    static func enumerate(maxHosts: Int? = nil) -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddrs_pointer(ifaddr) else { return [] }
        defer { freeifaddrs(ifaddr) }
        var primaryCandidate: String? = nil   // first active non-loopback IPv4 whose name starts with "en"
        var fallbackCandidate: String? = nil  // first active non-loopback IPv4 of any name
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP else { continue }
            guard (flags & IFF_LOOPBACK) != IFF_LOOPBACK else { continue }
            guard ifa.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var addr = ifa.ifa_addr.pointee
            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = getnameinfo(&addr, socklen_t(addr.sa_len), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST)
            guard r == 0, let ip = String(validatingUTF8: hostBuf) else { continue }
            let name = String(cString: ifa.ifa_name)
            if primaryCandidate == nil && name.hasPrefix("en") { primaryCandidate = ip }
            if fallbackCandidate == nil { fallbackCandidate = ip }
            if primaryCandidate != nil { break }
        }
        let chosen = primaryCandidate ?? fallbackCandidate
        var result: [String] = []
        if let ip = chosen { result = expandSlash24(ip: ip) }
        if let cap = maxHosts, result.count > cap {
            let stride = max(1, result.count / cap)
            result = Array(result.enumerated().compactMap { ($0.offset % stride == 0) ? $0.element : nil }.prefix(cap))
        }
        if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
            print("[Enumerate] baseIP=\(chosen ?? "nil") totalHosts=\(result.count)")
        }
        return result
    }

    private static func expandSlash24(ip: String) -> [String] {
        let parts = ip.split(separator: ".")
        guard parts.count == 4, let selfLast = Int(parts[3]) else { return [] }
        let base = "\(parts[0]).\(parts[1]).\(parts[2])."
        var ips: [String] = []
        ips.reserveCapacity(253)
        for host in 1...254 where host != selfLast { ips.append(base + String(host)) }
        return ips
    }
}

// Helper to silence optional pointer warnings in Swift 6 migration contexts
private func ifaddrs_pointer(_ ptr: UnsafeMutablePointer<ifaddrs>?) -> UnsafeMutablePointer<ifaddrs>? { ptr }
