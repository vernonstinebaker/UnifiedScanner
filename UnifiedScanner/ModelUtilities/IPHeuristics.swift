import Foundation

// Attribution: Logic adapted from Bonjour reference implementation (bestDisplayIP) conceptually.

public enum IPHeuristics {
    // Preference: private IPv4 (non-link-local) > other IPv4 > IPv6 link-local > any
    public static func bestDisplayIP(_ ips: Set<String>) -> String? {
        if ips.isEmpty { return nil }
        let ipv4Private = ips.filter { $0.isIPv4 && $0.isPrivateIPv4 }
        if let best = ipv4Private.sorted(by: stableSort).first { return best }
        let ipv4 = ips.filter { $0.isIPv4 }
        if let best = ipv4.sorted(by: stableSort).first { return best }
        let ipv6 = ips.filter { $0.contains(":") }
        return ipv6.sorted(by: stableSort).first ?? ips.sorted(by: stableSort).first
    }

    // Marked @inline(__always) and nonisolated to avoid unintended MainActor inference in Swift 6
    nonisolated private static func stableSort(_ a: String, _ b: String) -> Bool { a < b }
}

fileprivate extension String {
    var isIPv4: Bool { components(separatedBy: ".").count == 4 && self.range(of: "[^0-9.]", options: .regularExpression) == nil }
    var isPrivateIPv4: Bool {
        guard isIPv4 else { return false }
        let parts = components(separatedBy: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch parts[0] {
        case 10: return true
        case 172 where (16...31).contains(parts[1]): return true
        case 192 where parts[1] == 168: return true
        default: return false
        }
    }
}
