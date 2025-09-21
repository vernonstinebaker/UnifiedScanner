import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if os(macOS)
import Network
#endif

/// Platform-aware service that exposes the current ARP table and helper routines
/// to encourage population (e.g. lightweight UDP probes). On macOS the service
/// uses the NET_RT_DUMP route table to enumerate entries, which works inside the
/// sandbox without shelling out to `/usr/sbin/arp`.
public final class ARPService: @unchecked Sendable { // @unchecked because NWConnection callbacks execute on udpQueue; all mutable state confined to that queue
    public struct ARPEntry: Sendable {
        public let ipAddress: String
        public let macAddress: String
        public let interface: String
        public let isStatic: Bool

        public init(ipAddress: String, macAddress: String, interface: String, isStatic: Bool = false) {
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.interface = interface
            self.isStatic = isStatic
        }
    }

    private static var loggingEnabled: Bool { true }

    #if os(macOS)
    private let udpQueue = DispatchQueue(label: "arpservice.udpQueue")
    #endif

    public init() {}

    /// Returns the complete ARP table available to the current process.
    public func fullTable() async -> [ARPEntry] {
        #if os(macOS)
        do {
            return try await Self.loadRouteDump()
        } catch {
            if Self.loggingEnabled { LoggingService.warn("route dump failed: \(error)") }
            return []
        }
        #else
        return []
        #endif
    }

    /// Convenience helper returning a map of IP → MAC for the supplied host set.
    /// When `ips` is empty, the entire table is returned.
    public func getMACAddresses(for ips: Set<String>, delaySeconds: Double = 0.0) async -> [String: String] {
        if delaySeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        let entries = await fullTable()
        var map: [String: String] = [:]
        if ips.isEmpty {
            for entry in entries { map[entry.ipAddress] = entry.macAddress }
        } else {
            for entry in entries where ips.contains(entry.ipAddress) {
                map[entry.ipAddress] = entry.macAddress
            }
        }
        if Self.loggingEnabled {
            let addressCountMessage = "resolved \(map.count)/\(ips.isEmpty ? entries.count : ips.count) ARP addresses"; LoggingService.debug(addressCountMessage)
        }
        return map
    }

    /// Dispatches lightweight UDP datagrams to each host to help populate the ARP table.
    /// This is a no-op on platforms that cannot perform raw socket sends from userland.
    public func populateCache(for hosts: [String], broadcast: Bool = true, ports: [UInt16]? = nil, timeout: TimeInterval = 0.25) async {
#if os(macOS)
        guard !hosts.isEmpty else { return }
        let resolvedPorts = ports ?? Self.defaultUDPPorts
        for host in hosts {
            for port in resolvedPorts {
                sendUDP(host: host, port: port, timeout: timeout)
            }
        }
        if broadcast, let broadcastIP = Self.broadcastAddress(from: hosts.first) {
            for port in resolvedPorts {
                sendUDP(host: broadcastIP, port: port, timeout: timeout)
            }
        }
        // Allow a brief window for responses / ARP entries to materialise.
        try? await Task.sleep(nanoseconds: UInt64((timeout * 1_000_000_000).rounded()))
        #endif
    }

    // MARK: - Route Dump (macOS)

    #if os(macOS)
    private static func loadRouteDump() async throws -> [ARPEntry] {
        let mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]
        var bufferSize: size_t = 0
        var localMib = mib
        if sysctl(&localMib, UInt32(localMib.count), nil, &bufferSize, nil, 0) != 0 {
            throw NSError(domain: "ARPService", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "sysctl sizing failed: \(errno)"])
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<UInt64>.alignment)
        defer { buffer.deallocate() }

        localMib = mib
        if sysctl(&localMib, UInt32(localMib.count), buffer, &bufferSize, nil, 0) != 0 {
            throw NSError(domain: "ARPService", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "sysctl load failed: \(errno)"])
        }

        var entries: [ARPEntry] = []
        var pointer = buffer
        let end = buffer.advanced(by: bufferSize)

        while pointer < end {
            let message = pointer.assumingMemoryBound(to: rt_msghdr.self).pointee
            if (message.rtm_flags & RTF_LLINFO) != 0 {
                if let entry = parseEntry(message: message, basePointer: pointer) {
                    entries.append(entry)
                }
            }
            pointer = pointer.advanced(by: Int(message.rtm_msglen))
        }
        return entries
    }

    static func parseEntry(message: rt_msghdr, basePointer: UnsafeMutableRawPointer) -> ARPEntry? {
        var destinationIP: String?
        var macAddress: String?
        var interface: String?
        let isStatic = (message.rtm_flags & RTF_STATIC) != 0

        var rawPointer = UnsafeRawPointer(basePointer).advanced(by: MemoryLayout<rt_msghdr>.size)
        for bit in 0..<RTAX_MAX where (message.rtm_addrs & (1 << bit)) != 0 {
            let sockaddrHeader = rawPointer.assumingMemoryBound(to: sockaddr.self).pointee
            switch (Int32(sockaddrHeader.sa_family), bit) {
case (AF_INET, RTAX_DST):
                    let sin = rawPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var addr = sin.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                destinationIP = buffer.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.flatMap { decodeCString($0, context: "ARPService.routeDump.destination") } ?? ""
                }
            case (AF_LINK, RTAX_GATEWAY):
                let sdl = rawPointer.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                interface = extractInterfaceName(from: sdl, dataPointer: rawPointer)
                if Int(sdl.sdl_alen) == 6 {
                    let macStart = rawPointer.advanced(by: Self.sockaddrDLDataOffset + Int(sdl.sdl_nlen) + Int(sdl.sdl_slen))
                    macAddress = macString(from: macStart.assumingMemoryBound(to: UInt8.self))
                }
            default:
                break
            }
            rawPointer = advancePointer(from: rawPointer, sockaddr: sockaddrHeader)
        }

        guard let ip = destinationIP, let mac = macAddress else { return nil }
        return ARPEntry(ipAddress: ip, macAddress: mac, interface: interface ?? "", isStatic: isStatic)
    }

    static func advancePointer(from pointer: UnsafeRawPointer, sockaddr: sockaddr) -> UnsafeRawPointer {
        var length = Int(sockaddr.sa_len)
        if length == 0 { length = MemoryLayout<sockaddr>.size }
        if length & 3 != 0 { length += 4 - (length & 3) }
        return pointer.advanced(by: length)
    }

    static func extractInterfaceName(from sdl: sockaddr_dl, dataPointer: UnsafeRawPointer) -> String? {
        guard sdl.sdl_nlen > 0 else { return nil }
        let nameStart = dataPointer.advanced(by: sockaddrDLDataOffset)
        let bytes = nameStart.assumingMemoryBound(to: UInt8.self)
        return String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sdl.sdl_nlen)), encoding: .utf8)
    }

    static func macString(from pointer: UnsafePointer<UInt8>) -> String {
        (0..<6).map { String(format: "%02X", pointer[$0]) }.joined(separator: ":")
    }

    static var sockaddrDLDataOffset: Int {
        MemoryLayout.offset(of: \sockaddr_dl.sdl_data) ?? 8
    }

    func sendUDP(host: String, port: UInt16, timeout: TimeInterval) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        udpQueue.async {
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
            connection.start(queue: self.udpQueue)
            connection.send(content: Data([0x00]), completion: .contentProcessed { _ in
                connection.cancel()
            })
            self.udpQueue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
            }
        }
    }

    static func broadcastAddress(from host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }
        var parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        parts[3] = "255"
        return parts.joined(separator: ".")
    }
    #endif

    static var defaultUDPPorts: [UInt16] { [137, 1900, 5353, 67, 68] }
}
