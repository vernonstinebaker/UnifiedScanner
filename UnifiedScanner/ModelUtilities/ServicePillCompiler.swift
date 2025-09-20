import Foundation

struct ServicePill: Identifiable, Hashable {
    let id: String
    let label: String
    let type: NetworkService.ServiceType?
    let isOverflow: Bool
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
            Entry(key: key, count: value.count)
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
            pills.append(ServicePill(id: pillID, label: label, type: entry.key.type, isOverflow: false))
        }

        var overflow = 0
        if entries.count > limit {
            overflow = entries.count - limit
            pills.append(ServicePill(id: "overflow-\(overflow)", label: "+\(overflow)", type: nil, isOverflow: true))
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
        if service.isStandardPort { return resolvedBase }
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
    }
}
