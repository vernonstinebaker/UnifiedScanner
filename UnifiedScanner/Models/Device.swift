import Foundation

public struct Device: Identifiable, Hashable, Codable, Sendable {
    // MARK: - Nested Types
    public struct Classification: Hashable, Codable, Sendable {
        public let formFactor: DeviceFormFactor?
        public let rawType: String?
        public let confidence: ClassificationConfidence
        public let reason: String
        public let sources: [String] // e.g. ["mdns:airplay", "vendor:apple"]
        public init(formFactor: DeviceFormFactor?, rawType: String?, confidence: ClassificationConfidence, reason: String, sources: [String]) {
            self.formFactor = formFactor
            self.rawType = rawType
            self.confidence = confidence
            self.reason = reason
            self.sources = sources
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, primaryIP, ips, hostname, macAddress, vendor, modelHint, classification, discoverySources, rttMillis, services, openPorts, fingerprints, firstSeen, lastSeen, isOnlineOverride, name, autoName
    }

    // MARK: - Identity & Core Signals
    public let id: String // Stable identity (prefer MAC > primary IP > hostname, else UUID)
    public var primaryIP: String?
    public var ips: Set<String>
    public var hostname: String?
    public var macAddress: String?
    public var vendor: String?
    public var modelHint: String?
    public var name: String? // User override
    public var autoName: String? // Derived display name

    // MARK: - Classification
    public var classification: Classification?

    // MARK: - Discovery & Metrics
    public var discoverySources: Set<DiscoverySource>
    public var rttMillis: Double?

    // MARK: - Services & Ports
    public var services: [NetworkService]
    public var openPorts: [Port]

    // MARK: - Additional Fingerprints
    public var fingerprints: [String: String]?

    // MARK: - Timeline
    public var firstSeen: Date?
    public var lastSeen: Date?

    // MARK: - Overrides
    public var isOnlineOverride: Bool?

    // MARK: - Derived
    public var isOnline: Bool { isOnlineOverride ?? recentlySeen }
    public var recentlySeen: Bool { guard let ls = lastSeen else { return false }; return Date().timeIntervalSince(ls) < DeviceConstants.onlineGraceInterval }
    public var displayServices: [NetworkService] { ServiceDeriver.displayServices(services: services, openPorts: openPorts) }
    public var bestDisplayIP: String? { primaryIP ?? IPHeuristics.bestDisplayIP(ips) }

    // MARK: - Init
    public init(id: String? = nil,
                primaryIP: String? = nil,
                ips: Set<String> = [],
                hostname: String? = nil,
                macAddress: String? = nil,
                vendor: String? = nil,
                modelHint: String? = nil,
                classification: Classification? = nil,
                name: String? = nil,
                autoName: String? = nil,
                discoverySources: Set<DiscoverySource> = [],
                rttMillis: Double? = nil,
                services: [NetworkService] = [],
                openPorts: [Port] = [],
                fingerprints: [String: String]? = nil,
                firstSeen: Date? = nil,
                lastSeen: Date? = nil,
                isOnlineOverride: Bool? = nil) {
        self.primaryIP = primaryIP
        self.ips = ips
        self.hostname = hostname
        self.macAddress = macAddress
        self.vendor = vendor
        self.modelHint = modelHint
        self.name = name
        self.autoName = autoName
        self.classification = classification
        self.discoverySources = discoverySources
        self.rttMillis = rttMillis
        self.services = services
        self.openPorts = openPorts
        self.fingerprints = fingerprints
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isOnlineOverride = isOnlineOverride
        // Compute ID preference order
        if let explicit = id {
            self.id = explicit
        } else if let mac = macAddress, !mac.isEmpty {
            self.id = Device.normalizeMAC(mac)
        } else if let pip = primaryIP {
            self.id = pip
        } else if let host = hostname, !host.isEmpty {
            self.id = host
        } else {
            self.id = UUID().uuidString
        }
    }

    // MARK: - Helpers
    public static func normalizeMAC(_ mac: String) -> String {
        mac.uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .split(separator: ":")
            .map { String($0).paddingLeft(to: 2, with: "0") }
            .joined(separator: ":")
    }

    // MARK: - Mutation helpers
    public func withDiscoverySources(_ sources: Set<DiscoverySource>) -> Device {
        var copy = self
        copy.discoverySources = sources
        return copy
    }

    public func withDiscoverySources(_ sources: [DiscoverySource]) -> Device {
        return withDiscoverySources(Set(sources))
    }
}

// MARK: - Supporting Types
public enum DeviceFormFactor: String, Codable, CaseIterable, Sendable { case router, computer, laptop, tv, printer, gameConsole, phone, tablet, accessory, iot, server, camera, speaker, hub, unknown }
public enum ClassificationConfidence: String, Codable, CaseIterable, Sendable { case unknown, low, medium, high }
public enum DiscoverySource: String, Codable, CaseIterable, Sendable { case mdns, arp, ping, ssdp, portScan, httpProbe, reverseDNS, manual, unknown }

public struct NetworkService: Identifiable, Hashable, Codable, Sendable {
    public enum ServiceType: String, Codable, CaseIterable, Sendable { case http, https, ssh, dns, dhcp, smb, ftp, vnc, airplay, airplayAudio, homekit, chromecast, spotify, printer, ipp, telnet, other }
    public let id: UUID
    public let name: String
    public let type: ServiceType
    public let rawType: String?
    public let port: Int?
    public let isStandardPort: Bool
    public init(id: UUID = UUID(), name: String, type: ServiceType, rawType: String?, port: Int?, isStandardPort: Bool) {
        self.id = id
        self.name = name
        self.type = type
        self.rawType = rawType
        self.port = port
        self.isStandardPort = isStandardPort
    }
    public init(id: UUID = UUID(), name: String, type: ServiceType, port: Int?, isStandardPort: Bool) {
        self.init(id: id, name: name, type: type, rawType: nil, port: port, isStandardPort: isStandardPort)
    }
}

public struct Port: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable { case open, closed, filtered }
    public let id: UUID
    public let number: Int
    public let transport: String
    public let serviceName: String
    public let description: String
    public let status: Status
    public let lastSeenOpen: Date?
    public init(id: UUID = UUID(), number: Int, transport: String = "tcp", serviceName: String, description: String, status: Status, lastSeenOpen: Date?) {
        self.id = id
        self.number = number
        self.transport = transport
        self.serviceName = serviceName
        self.description = description
        self.status = status
        self.lastSeenOpen = lastSeenOpen
    }
}

public enum DeviceConstants { public static let onlineGraceInterval: TimeInterval = 300 }

// MARK: - Internal Extensions
fileprivate extension String {
    func paddingLeft(to length: Int, with pad: Character) -> String {
        if count >= length { return self }
        return String(repeatElement(pad, count: length - count)) + self
    }
}