import Foundation

// Attribution: Concept blended from netscan ServiceMapper & Bonjour service name formatting.

public enum ServiceDeriver {
    // Map common ports to canonical service types / names (minimal subset; extend later)
    static let wellKnownPorts: [Int: (NetworkService.ServiceType, String)] = [
        80: (.http, "HTTP"),
        443: (.https, "HTTPS"),
        22: (.ssh, "SSH"),
        53: (.dns, "DNS"),
        139: (.smb, "SMB"),
        445: (.smb, "SMB"),
        515: (.printer, "LPD"),
        631: (.ipp, "IPP"),
        3689: (.airplayAudio, "DAAP"),
        7000: (.airplay, "AirPlay"),
    ]

    // Service type string normalization from raw mDNS types
    static func normalize(rawType: String) -> (NetworkService.ServiceType, String) {
        let lower = rawType.lowercased()
        if lower.contains("airplay") { return (.airplay, "AirPlay") }
        if lower.contains("_raop.") { return (.airplayAudio, "AirPlay Audio") }
        if lower.contains("homekit") || lower.contains("hap") { return (.homekit, "HomeKit") }
        if lower.contains("_ssh.") { return (.ssh, "SSH") }
        if lower.contains("_https.") { return (.https, "HTTPS") }
        if lower.contains("_http.") { return (.http, "HTTP") }
        if lower.contains("_ipp.") { return (.ipp, "IPP") }
        if lower.contains("_printer.") { return (.printer, "Printer") }
        if lower.contains("_spotify.") { return (.spotify, "Spotify") }
        if lower.contains("_chromecast.") || lower.contains("_googlecast.") { return (.chromecast, "Chromecast") }
        if lower.contains("_rfb.") { return (.vnc, "VNC") }
        if lower.contains("_sftp-ssh.") { return (.ssh, "SFTP/SSH") }
        if lower.contains("_afpovertcp.") { return (.other, "AFP File Sharing") }
        if lower.contains("_workstation.") { return (.other, "Workstation") }
        if lower.contains("_device-info.") { return (.other, "Device Info") }
        if lower.contains("_companion-link.") { return (.other, "Companion Link") }
        if lower.contains("_remotepairing.") { return (.other, "Remote Pairing") }
        if lower.contains("_touch-able.") { return (.other, "Touch Able") }
        if lower.contains("_sleep-proxy.") { return (.other, "Sleep Proxy") }
        if lower.contains("_apple-mobdev2.") { return (.other, "Apple Dev") }
        return (.other, rawType.trimmingCharacters(in: CharacterSet(charactersIn: "_")))
    }

    // Merge explicit services + inferred open ports into deduped display list.
    public static func displayServices(services: [NetworkService], openPorts: [Port]) -> [NetworkService] {
        var collected: [ServiceKey: NetworkService] = [:]

        // 1. Start with explicitly discovered services
        for svc in services {
            let key = ServiceKey(type: svc.type, port: svc.port)
            if let existing = collected[key] {
                // Prefer the one with a more descriptive name (longer) if types equal
                if svc.name.count > existing.name.count { collected[key] = svc }
            } else {
                collected[key] = svc
            }
        }

        // 2. Add port-derived services if not already represented by same (type, port)
        for port in openPorts where port.status == .open {
            if let mapped = wellKnownPorts[port.number] {
                let key = ServiceKey(type: mapped.0, port: port.number)
                if collected[key] == nil {
                    let svc = NetworkService(name: mapped.1, type: mapped.0, rawType: nil, port: port.number, isStandardPort: true)
                    collected[key] = svc
                }
            }
        }

        // 3. Return stable sorted order: type enum order then port ascending then name
        return collected.values.sorted { a, b in
            if a.type == b.type {
                if a.port == b.port { return a.name < b.name }
                return (a.port ?? Int.max) < (b.port ?? Int.max)
            }
            return a.type.sortIndex < b.type.sortIndex
        }
    }

    // Utility to construct service from raw discovery if needed externally
    public static func makeService(fromRaw rawType: String, port: Int?) -> NetworkService {
        let (stype, name) = normalize(rawType: rawType)
        let standard = port.map { wellKnownPorts[$0]?.0 == stype } ?? false
        return NetworkService(name: name, type: stype, rawType: rawType, port: port, isStandardPort: standard)
    }

    // Key for grouping
    private struct ServiceKey: Hashable { let type: NetworkService.ServiceType; let port: Int? }
}

extension NetworkService.ServiceType {
    var sortIndex: Int {
        switch self {
        case .http: return 0
        case .https: return 1
        case .ssh: return 2
        case .dns: return 3
        case .dhcp: return 4
        case .smb: return 5
        case .ftp: return 6
        case .vnc: return 7
        case .airplay: return 8
        case .airplayAudio: return 9
        case .homekit: return 10
        case .chromecast: return 11
        case .spotify: return 12
        case .printer: return 13
        case .ipp: return 14
        case .telnet: return 15
        case .other: return 16
        }
    }
}
