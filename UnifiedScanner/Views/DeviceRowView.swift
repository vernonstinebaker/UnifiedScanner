import SwiftUI

struct DeviceRowView: View {
    let device: Device
    var isSelected: Bool = false

    private var discoverySources: [DiscoverySource] {
        device.discoverySources
            .filter { $0 != .unknown }
            .sorted(by: discoveryOrder)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space(.lg)) {
            deviceIcon
            VStack(alignment: .leading, spacing: Theme.space(.sm)) {
                headerRow
                metaRow
                if !device.displayServices.isEmpty {
                    ServiceTagsView(services: device.displayServices, maxVisible: 4)
                }
            }
            Spacer()
            indicatorColumn
        }
.padding(Theme.space(.lg))
.background(
    RoundedRectangle(cornerRadius: Theme.radius(.xl), style: .continuous)
        .fill(Theme.color(.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius(.xl), style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.035 : 0))
        )
)
.cornerRadius(Theme.radius(.xl))
.overlay(
    RoundedRectangle(cornerRadius: Theme.radius(.xl))
        .stroke(Theme.color(.separator), lineWidth: isSelected ? 2 : 1)
)
    }

    private var deviceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radius(.lg))
                .fill(Theme.color(.bgElevated))
                .frame(width: 48, height: 48)
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Theme.color(.accentPrimary))
        }
    }

    private var headerRow: some View {
HStack(spacing: Theme.space(.sm)) {
    Text(primaryTitle)
        .font(Theme.Typography.headline)
        .foregroundColor(Theme.color(.textPrimary))
        .lineLimit(1)
    if let classification = device.classification {
        ConfidenceBadge(confidence: classification.confidence)
    }
    Spacer(minLength: 0)
}
    }

private var metaRow: some View {
    VStack(alignment: .leading, spacing: Theme.space(.xs)) {
        if let vendor = device.vendor {
            Text(vendor)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
                .lineLimit(1)
        }
        if let ip = device.bestDisplayIP {
            Text(ip)
                .font(Theme.Typography.mono)
                .foregroundColor(Theme.color(.accentPrimary))
        }
        HStack(spacing: Theme.space(.sm)) {
            if let mac = device.macAddress, !mac.isEmpty {
                Text(mac.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.color(.textTertiary))
            }
            if let host = device.hostname, host != primaryTitle {
                Text(host)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
                    .lineLimit(1)
            }
        }
    }
}

    private var indicatorColumn: some View {
        VStack(alignment: .trailing, spacing: Theme.space(.sm)) {
            Circle()
                .fill(device.isOnline ? Theme.color(.statusOnline) : Theme.color(.statusOffline))
                .frame(width: 12, height: 12)
                .shadow(color: device.isOnline ? Theme.color(.statusOnline).opacity(0.6) : .clear,
                        radius: 3,
                        y: 1)
                .accessibilityLabel(device.isOnline ? "Online" : "Offline")
            primaryDiscoveryBadge
        }
    }

private var primaryTitle: String {
    device.hostname ?? device.bestDisplayIP ?? device.id
}

    private var iconName: String {
        if let ff = device.classification?.formFactor {
            switch ff {
            case .router: return "network"
            case .computer, .laptop: return "desktopcomputer"
            case .tv: return "tv"
            case .printer: return "printer"
            case .phone: return "iphone"
            case .tablet: return "ipad"
            case .server: return "server.rack"
            case .camera: return "camera"
            case .speaker: return "hifispeaker.fill"
            case .iot, .hub, .accessory: return "dot.radiowaves.left.and.right"
            case .gameConsole: return "gamecontroller"
            case .unknown: return "desktopcomputer"
            }
        }
        if device.displayServices.contains(where: { $0.type == .airplay || $0.type == .airplayAudio }) { return "airplayvideo" }
        if device.displayServices.contains(where: { $0.type == .printer }) { return "printer" }
        if device.displayServices.contains(where: { $0.type == .http || $0.type == .https }) { return "server.rack" }
        return "desktopcomputer"
    }

    private func discoveryOrder(_ lhs: DiscoverySource, _ rhs: DiscoverySource) -> Bool {
        let ranking: [DiscoverySource] = [.arp, .ping, .mdns, .ssdp, .portScan, .reverseDNS, .manual, .unknown]
        let li = ranking.firstIndex(of: lhs) ?? ranking.count
        let ri = ranking.firstIndex(of: rhs) ?? ranking.count
        if li == ri { return lhs.rawValue < rhs.rawValue }
        return li < ri
    }

    private var primaryDiscoverySource: DiscoverySource? {
        discoverySources.first
    }

    @ViewBuilder
    private var primaryDiscoveryBadge: some View {
        if let source = primaryDiscoverySource {
            let style = Theme.discoveryStyle(for: source)
            Text(style.title)
                .font(Theme.Typography.tag)
                .padding(.horizontal, Theme.space(.sm))
                .padding(.vertical, Theme.space(.xs))
                .background(style.color.opacity(0.18))
                .foregroundColor(style.color)
                .clipShape(Capsule())
        }
    }
}

struct DiscoveryPillsView: View {
    let sources: [DiscoverySource]

    var body: some View {
        HStack(spacing: Theme.space(.sm)) {
            ForEach(sources.indices, id: \.self) { index in
                let source = sources[index]
                let style = Theme.discoveryStyle(for: source)
                Text(style.title)
                    .font(Theme.Typography.tag)
                    .padding(.horizontal, Theme.space(.sm))
                    .padding(.vertical, Theme.space(.xs))
                    .background(style.color.opacity(0.18))
                    .foregroundColor(style.color)
                    .cornerRadius(Theme.radius(.sm))
            }
        }
    }
}

struct ServiceTagsView: View {
    let services: [NetworkService]
    var maxVisible: Int? = nil

    var body: some View {
        let compilation = ServicePillCompiler.compile(services: services, maxVisible: maxVisible)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.space(.sm)) {
                ForEach(compilation.pills) { pill in
                    pillView(for: pill)
                }
            }
        }
    }

    @ViewBuilder
    private func pillView(for pill: ServicePill) -> some View {
        if pill.isOverflow {
            Text(pill.label)
                .font(Theme.Typography.tag)
                .padding(.horizontal, Theme.space(.sm))
                .padding(.vertical, Theme.space(.xs))
                .background(Theme.color(.bgElevated))
                .foregroundColor(Theme.color(.textSecondary))
                .clipShape(Capsule())
        } else if let type = pill.type {
            let style = Theme.style(for: type)
            Text(pill.label)
                .font(Theme.Typography.tag)
                .padding(.horizontal, Theme.space(.sm))
                .padding(.vertical, Theme.space(.xs))
                .background(style.color.opacity(0.18))
                .foregroundColor(style.color)
                .clipShape(Capsule())
        } else {
            Text(pill.label)
                .font(Theme.Typography.tag)
                .padding(.horizontal, Theme.space(.sm))
                .padding(.vertical, Theme.space(.xs))
                .background(Theme.color(.bgElevated))
                .foregroundColor(Theme.color(.textSecondary))
                .clipShape(Capsule())
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: ClassificationConfidence

    var body: some View {
        Text(label)
            .font(Theme.Typography.tag)
            .padding(.horizontal, Theme.space(.sm))
            .padding(.vertical, Theme.space(.xs))
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius(.sm)))
            .accessibilityLabel("Confidence \(label)")
    }

    private var label: String {
        switch confidence {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        case .unknown: return "?"
        }
    }

    private var color: Color {
        switch confidence {
        case .high: return Theme.color(.statusOnline)
        case .medium: return Theme.color(.accentWarn)
        case .low: return Theme.color(.accentDanger)
        case .unknown: return Theme.color(.accentMuted)
        }
    }
}
