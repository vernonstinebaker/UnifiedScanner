import Foundation
import Darwin

// MARK: - Host Enumeration Abstraction
@preconcurrency protocol HostEnumerator: Sendable {
    func enumerate(maxHosts: Int?) -> [String]
}

/// Generates a /24 host list for the primary active IPv4 interface using
/// lightweight helpers adapted from the PingScanner project.
struct LocalSubnetEnumerator: HostEnumerator {
    func enumerate(maxHosts: Int? = nil) -> [String] {
        guard let ip = Self.primaryIPv4Address() else { return [] }
        guard let block = Self.cidrBlock(for: ip, prefix: 24) else { return [] }
        var hosts = block.hostAddresses()
        // Filter link-local 169.254/16 (not useful for broad scans) and multicast/broadcast edge cases
        hosts = hosts.filter { !$0.hasPrefix("169.254.") }
        if let limit = maxHosts, limit > 0, hosts.count > limit {
            hosts = Array(hosts.prefix(limit))
        }
        let totalHosts = hosts.count; LoggingService.debug("enumerate baseIP=\(ip) totalHosts=\(totalHosts)")
        return hosts
    }

    static func primaryIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: String?
        var fallback: String?

        var pointer: UnsafeMutablePointer<ifaddrs>? = start
        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }
            guard let addrPtr = current.ifa_addr else { continue }
            let flags = Int32(current.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP else { continue }
            guard (flags & IFF_LOOPBACK) != IFF_LOOPBACK else { continue }
            guard addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let name = decodeCString(current.ifa_name, context: "LocalSubnetEnumerator.ifname") ?? ""
            var addr = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = buffer.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.flatMap { decodeCString($0, context: "LocalSubnetEnumerator.ip") } ?? ""
            }

            if preferred == nil && name.hasPrefix("en") { preferred = ip }
            if fallback == nil { fallback = ip }
            if preferred != nil { break }
        }

        return preferred ?? fallback
    }

    private static func cidrBlock(for ip: String, prefix: Int) -> CIDRBlock? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let base = parts.enumerated().map { index, value in
            index == 3 ? "0" : String(value)
        }.joined(separator: ".")
        return CIDRBlock(cidr: "\(base)/\(prefix)")
    }
}

struct IPv4Network: Sendable {
    let networkAddress: UInt32
    let netmask: UInt32
}

extension LocalSubnetEnumerator {
    static func activeIPv4Networks() -> [IPv4Network] {
        var networks: [IPv4Network] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return networks }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = start
        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }
            guard let addrPtr = current.ifa_addr, let maskPtr = current.ifa_netmask else { continue }
            let flags = Int32(current.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP else { continue }
            guard (flags & IFF_LOOPBACK) != IFF_LOOPBACK else { continue }
            guard addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let ifName = decodeCString(current.ifa_name, context: "LocalSubnetEnumerator.network.ifname")?.lowercased() ?? ""
            let disallowedPrefixes = ["utun", "ppp", "ipsec", "lo", "gif"]
            guard !disallowedPrefixes.contains(where: { ifName.hasPrefix($0) }) else { continue }

            let sinAddr = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let sinMask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let addr = UInt32(bigEndian: sinAddr.sin_addr.s_addr)
            let maskRaw = UInt32(bigEndian: sinMask.sin_addr.s_addr)
            guard maskRaw != 0 else { continue }
            let network = addr & maskRaw
            let candidate = IPv4Network(networkAddress: network, netmask: maskRaw)
            if !networks.contains(where: { $0.networkAddress == candidate.networkAddress && $0.netmask == candidate.netmask }) {
                networks.append(candidate)
            }
        }

        return networks
    }
}

// MARK: - CIDR Utilities (adapted from PingScanner)
struct CIDRBlock: Equatable {
    let baseAddress: UInt32
    let prefix: Int

    init?(cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefixValue = Int(parts[1]),
              (0...32).contains(prefixValue),
              let base = IPv4Parser.addressToUInt32(String(parts[0]))
        else {
            return nil
        }

        prefix = prefixValue
        let mask = prefix == 0 ? UInt32(0) : UInt32.max << (32 - prefix)
        baseAddress = base & mask
    }

    func hostAddresses(includeNetwork: Bool = false, includeBroadcast: Bool = false) -> [String] {
        if prefix == 32 {
            return [IPv4Parser.uint32ToAddress(baseAddress)]
        }

        let hostBits = 32 - prefix
        let hostCount = 1 << hostBits
        var addresses: [String] = []
        addresses.reserveCapacity(hostCount)

        for index in 0..<hostCount {
            let address = baseAddress + UInt32(index)
            if index == 0 && !includeNetwork && hostCount > 1 { continue }
            if index == hostCount - 1 && !includeBroadcast && hostCount > 1 { continue }
            addresses.append(IPv4Parser.uint32ToAddress(address))
        }
        return addresses
    }
}

enum IPv4Parser {
    static func addressToUInt32(_ address: String) -> UInt32? {
        var sin = in_addr()
        let result = address.withCString { inet_pton(AF_INET, $0, &sin) }
        guard result == 1 else { return nil }
        return UInt32(bigEndian: sin.s_addr)
    }

    static func uint32ToAddress(_ value: UInt32) -> String {
        var addr = in_addr(s_addr: value.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.flatMap { decodeCString($0, context: "IPv4Parser.uint32ToAddress") }
        } ?? ""
    }
}
