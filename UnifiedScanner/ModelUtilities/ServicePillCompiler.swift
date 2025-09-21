import Foundation

struct ServicePill: Identifiable, Hashable {
    let id: String
    let label: String
    let type: NetworkService.ServiceType?
    let isOverflow: Bool
    let serviceID: UUID?
    let port: Int?
}

enum ServicePillCompiler {
    static func compile(services: [NetworkService], maxVisible: Int? = nil) -> (pills: [ServicePill], overflow: Int) {
        guard !services.isEmpty else { return ([], 0) }

        var grouped: [GroupKey: [NetworkService]] = [:]
        for service in services {
            let label = displayLabel(for: service)
            let key = GroupKey(type: service.type, label: label)
            grouped[key, default: []].append(service)
        }

        var entries: [Entry] = grouped.map { key, value in
            Entry(key: key, count: value.count, firstID: value.first?.id, firstPort: value.first?.port)
        }

        entries.sort { lhs, rhs in
            if lhs.key.type.sortIndex == rhs.key.type.sortIndex {
                return lhs.key.label.localizedCaseInsensitiveCompare(rhs.key.label) == .orderedAscending
            }
            return lhs.key.type.sortIndex < rhs.key.type.sortIndex
        }

        let limit = normalizedLimit(maxVisible, total: entries.count)
        var pills: [ServicePill] = []
        pills.reserveCapacity(min(entries.count, limit) + 1)

        for (index, entry) in entries.enumerated() where index < limit {
            let baseLabel = entry.key.label
            let label = entry.count > 1 ? "\(baseLabel) ×\(entry.count)" : baseLabel
            let pillID = "\(entry.key.type.rawValue)|\(baseLabel)"
            pills.append(ServicePill(id: pillID,
                                     label: label,
                                     type: entry.key.type,
                                     isOverflow: false,
                                     serviceID: entry.firstID,
                                     port: entry.firstPort))
        }

        var overflow = 0
        if entries.count > limit {
            overflow = entries.count - limit
            pills.append(ServicePill(id: "overflow-\(overflow)", label: "+\(overflow)", type: nil, isOverflow: true, serviceID: nil, port: nil))
        }

        return (pills, overflow)
    }

    private static func normalizedLimit(_ maxVisible: Int?, total: Int) -> Int {
        guard let maxVisible, maxVisible >= 0 else { return total }
        return min(maxVisible, total)
    }

    private static func displayLabel(for service: NetworkService) -> String {
        let base = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = base.isEmpty ? service.type.rawValue.uppercased() : base
        guard let port = service.port else { return resolvedBase }
        if service.isStandardPort || service.type.matchesDefaultPort(port) { return resolvedBase }
        if resolvedBase.contains(":\(port)") { return resolvedBase }
        return "\(resolvedBase) :\(port)"
    }

    private struct GroupKey: Hashable {
        let type: NetworkService.ServiceType
        let label: String
    }

    private struct Entry {
        let key: GroupKey
        let count: Int
        let firstID: UUID?
        let firstPort: Int?
    }
}

private extension NetworkService.ServiceType {
    func matchesDefaultPort(_ port: Int) -> Bool {
        switch self {
        case .http where port == 80: return true
        case .https where port == 443: return true
        case .ssh where port == 22: return true
        case .dns where port == 53: return true
        case .dhcp where port == 67 || port == 68: return true
        case .smb where port == 139 || port == 445: return true
        case .ftp where port == 21: return true
        case .vnc where port == 5900: return true
        case .airplay where port == 7000: return true
        case .airplayAudio where port == 7000: return true
        case .homekit where (51826...51828).contains(port): return true
        case .chromecast where port == 8008 || port == 8009 || port == 8443: return true
        case .spotify where port == 57621: return true
        case .printer where port == 515: return true
        case .ipp where port == 631: return true
        case .telnet where port == 23: return true
        default: return false
        }
    }
}
