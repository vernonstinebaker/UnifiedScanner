import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

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
                    ServiceTagsView(services: device.displayServices, device: device, maxVisible: 4)
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
            Image(systemName: DeviceIconResolver.iconName(for: device))
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
        device.name ?? device.hostname ?? device.bestDisplayIP ?? device.id
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
    let device: Device
    var maxVisible: Int? = nil
    @Environment(\.openURL) private var openURL

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
            if let action = action(for: pill) {
                Button(action: action) {
                    Text(pill.label)
                        .font(Theme.Typography.tag)
                        .padding(.horizontal, Theme.space(.sm))
                        .padding(.vertical, Theme.space(.xs))
                        .background(style.color.opacity(0.18))
                        .foregroundColor(style.color)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(pill.label)
                    .font(Theme.Typography.tag)
                    .padding(.horizontal, Theme.space(.sm))
                    .padding(.vertical, Theme.space(.xs))
                    .background(style.color.opacity(0.18))
                    .foregroundColor(style.color)
                    .clipShape(Capsule())
            }
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

    private func action(for pill: ServicePill) -> (() -> Void)? {
        guard let type = pill.type, let host = hostForAction() else { return nil }
        let port = effectivePort(for: pill)
        switch type {
        case .http:
            return { openURLIfPossible(scheme: "http", host: host, port: port) }
        case .https:
            return { openURLIfPossible(scheme: "https", host: host, port: port) }
        case .ftp:
            return { openURLIfPossible(scheme: "ftp", host: host, port: port) }
        case .ssh:
            return { copyToClipboard("ssh \(host)") }
        default:
            return nil
        }
    }

    private func effectivePort(for pill: ServicePill) -> Int? {
        if let port = pill.port { return port }
        if let id = pill.serviceID, let match = services.first(where: { $0.id == id }) {
            return match.port
        }
        guard let type = pill.type else { return nil }
        return services.first(where: { $0.type == type })?.port
    }

    private func hostForAction() -> String? {
        if let hostname = device.hostname, !hostname.isEmpty { return hostname }
        if let ip = device.bestDisplayIP { return ip }
        if let primary = device.primaryIP { return primary }
        return nil
    }

    private func openURLIfPossible(scheme: String, host: String, port: Int?) {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port, shouldSpecifyPort(for: scheme, port: port) {
            components.port = port
        }
        guard let url = components.url else { return }
        openURL(url)
    }

    private func shouldSpecifyPort(for scheme: String, port: Int) -> Bool {
        switch scheme {
        case "http": return port != 80
        case "https": return port != 443
        case "ftp": return port != 21
        default: return true
        }
    }

    private func copyToClipboard(_ string: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = string
#elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
#endif
    }
}

enum DeviceIconResolver {
    static func iconName(for device: Device) -> String {
        let context = normalizedContext(for: device)

        if context.contains(where: { $0.contains("homepod") || $0.contains("audioaccessory") }) {
            return "homepod"
        }
        if context.contains(where: { $0.contains("appletv") || $0.contains("apple tv") }) {
            return "appletv"
        }
        if context.contains(where: { $0.contains("airport") }) {
            return "wifi.router"
        }
        if context.contains(where: { $0.contains("iphone") || $0.contains("ipod") }) {
            return "iphone"
        }
        if context.contains(where: { $0.contains("ipad") }) {
            return "ipad"
        }
        if context.contains(where: { $0.contains("macbook") }) {
            return "laptopcomputer"
        }
        if context.contains(where: { $0.contains("imac") }) {
            return "desktopcomputer"
        }
        if context.contains(where: { $0.contains("mac mini") || $0.contains("macmini") }) {
            return "macmini"
        }

        if let classification = device.classification {
            if let icon = iconName(for: classification.formFactor, context: context) {
                return icon
            }
        }

        if device.displayServices.contains(where: { $0.type == .airplay || $0.type == .airplayAudio }) {
            return "tv"
        }
        if device.displayServices.contains(where: { $0.type == .printer || $0.type == .ipp }) {
            return "printer"
        }

        if let hostname = device.hostname?.lowercased(), hostname.contains("router") || hostname.contains("gateway") {
            return "wifi.router"
        }

        return "wifi"
    }

    private static func iconName(for formFactor: DeviceFormFactor?, context: [String]) -> String? {
        guard let formFactor else { return nil }
        switch formFactor {
        case .router:
            return "wifi.router"
        case .computer:
            if context.contains(where: { $0.contains("macstudio") }) { return "desktopcomputer" }
            if context.contains(where: { $0.contains("macmini") || $0.contains("mac mini") }) { return "macmini" }
            if context.contains(where: { $0.contains("imac") }) { return "desktopcomputer" }
            if context.contains(where: { $0.contains("macbook") || $0.contains("laptop") }) { return "laptopcomputer" }
            return "desktopcomputer"
        case .laptop:
            if context.contains(where: { $0.contains("macbook") }) { return "laptopcomputer" }
            return "laptopcomputer"
        case .tv:
            return "tv"
        case .printer:
            return "printer"
        case .phone:
            return "iphone"
        case .tablet:
            return "ipad"
        case .server:
            return "server.rack"
        case .camera:
            return "camera"
        case .speaker:
            return context.contains(where: { $0.contains("speaker") || $0.contains("audio") }) ? "speaker.wave.2" : "speaker"
        case .iot, .hub, .accessory:
            return "dot.radiowaves.left.and.right"
        case .gameConsole:
            return "gamecontroller"
        case .unknown:
            return nil
        }
    }

    private static func normalizedContext(for device: Device) -> [String] {
        var pieces: [String] = []
        if let vendor = device.vendor { pieces.append(vendor) }
        if let modelHint = device.modelHint { pieces.append(modelHint) }
        if let hostname = device.hostname { pieces.append(hostname) }
        if let rawType = device.classification?.rawType { pieces.append(rawType) }
        if let fingerprints = device.fingerprints?.values {
            pieces.append(contentsOf: fingerprints)
        }
        return pieces
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }
}
