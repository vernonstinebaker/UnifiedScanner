import Foundation

/// Service for reading the system's ARP table to capture MAC addresses
/// for IP addresses that have been recently contacted.
public final class ARPTableReader {
    public struct ARPEntry: Sendable {
        public let ipAddress: String
        public let macAddress: String
        public let interface: String
        public let isPermanent: Bool

        public init(ipAddress: String, macAddress: String, interface: String, isPermanent: Bool = false) {
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.interface = interface
            self.isPermanent = isPermanent
        }
    }

    private static let infoLoggingEnabled: Bool = (ProcessInfo.processInfo.environment["ARP_INFO_LOG"] == "1")

    public init() {}

    /// Read the current ARP table and return entries for the specified IP addresses
    public func readARPTable(for ips: Set<String>) async -> [ARPEntry] {
        let logging = Self.infoLoggingEnabled
        if logging { print("[ARP] reading ARP table for \(ips.count) IPs") }

        do {
            let entries = try await Self.readARPTableSystem()
            let filtered = entries.filter { ips.contains($0.ipAddress) }

            if logging {
                print("[ARP] found \(entries.count) total entries, \(filtered.count) matching requested IPs")
                for entry in filtered {
                    print("[ARP] \(entry.ipAddress) -> \(entry.macAddress) (\(entry.interface))")
                }
            }

            return filtered
        } catch {
            if logging { print("[ARP] error reading ARP table: \(error)") }
            return []
        }
    }

    /// Read all current ARP table entries from the system
    private static func readARPTableSystem() async throws -> [ARPEntry] {
        #if os(macOS)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                    process.arguments = ["-a", "-n"] // -n to avoid DNS lookups

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        throw NSError(domain: "ARPTableReader", code: Int(process.terminationStatus),
                                    userInfo: [NSLocalizedDescriptionKey: "arp command failed"])
                    }

                    let entries = Self.parseARPOutput(output)
                    continuation.resume(returning: entries)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        // iOS: ARP table reading not available via Process
        // Return empty array - ARP functionality will be limited on iOS
        return []
        #endif
    }

    /// Parse the output from `arp -a -n` command
    private static func parseARPOutput(_ output: String) -> [ARPEntry] {
        var entries: [ARPEntry] = []

        let lines = output.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Parse format: "? (192.168.1.1) at 00:11:22:33:44:55 on en1 ifscope permanent [ethernet]"
            let components = trimmed.split(separator: " ").filter { !$0.isEmpty }

            guard components.count >= 4 else { continue }

            // Find IP address in parentheses
            var ipAddress = ""
            for component in components {
                if component.hasPrefix("(") && component.hasSuffix(")") {
                    ipAddress = String(component.dropFirst().dropLast())
                    break
                }
            }

            guard !ipAddress.isEmpty else { continue }

            // Find MAC address (should be "at" followed by MAC)
            var macAddress = ""
            var foundAt = false
            for component in components {
                if component == "at" {
                    foundAt = true
                    continue
                }
                if foundAt && component != "(incomplete)" {
                    macAddress = String(component)
                    break
                }
            }

            guard !macAddress.isEmpty && macAddress != "(incomplete)" else { continue }

            // Find interface (should be "on" followed by interface name)
            var interface = ""
            var foundOn = false
            for component in components {
                if component == "on" {
                    foundOn = true
                    continue
                }
                if foundOn {
                    interface = String(component)
                    break
                }
            }

            // Check if permanent
            let isPermanent = components.contains("permanent")

            let entry = ARPEntry(ipAddress: ipAddress,
                               macAddress: macAddress,
                               interface: interface,
                               isPermanent: isPermanent)
            entries.append(entry)
        }

        return entries
    }

    /// Get MAC addresses for a batch of IP addresses, with optional delay to allow ARP table population
    public func getMACAddresses(for ips: Set<String>, delaySeconds: Double = 2.0) async -> [String: String] {
        let logging = Self.infoLoggingEnabled

        if delaySeconds > 0 {
            if logging { print("[ARP] waiting \(delaySeconds)s for ARP table population") }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }

        let entries = await readARPTable(for: ips)
        var ipToMac: [String: String] = [:]

        for entry in entries {
            ipToMac[entry.ipAddress] = entry.macAddress
        }

        if logging {
            print("[ARP] resolved \(ipToMac.count)/\(ips.count) MAC addresses")
        }

        return ipToMac
    }
}