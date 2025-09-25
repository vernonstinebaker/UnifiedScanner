import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum DeviceDetailAction: Equatable {
    case openURL(URL)
    case copy(String)
}

@MainActor
final class DeviceDetailViewModel: ObservableObject {
    struct PortInteraction: Equatable {
        let accessibilityLabel: String
        let action: DeviceDetailAction
    }

    @Published private(set) var device: Device

    init(device: Device) {
        self.device = device
    }

    func update(device: Device) {
        self.device = device
    }

    func interaction(for port: Port) -> PortInteraction? {
        guard port.status == .open else { return nil }
        guard let host = hostForPortAction() else { return nil }

        if let type = inferredServiceType(for: port) {
            switch type {
            case .http:
                if let url = urlFor(scheme: "http", host: host, port: port.number) {
                    return PortInteraction(accessibilityLabel: "Open HTTP port \(port.number) on \(host)",
                                            action: .openURL(url))
                }
            case .https:
                if let url = urlFor(scheme: "https", host: host, port: port.number) {
                    return PortInteraction(accessibilityLabel: "Open HTTPS port \(port.number) on \(host)",
                                            action: .openURL(url))
                }
            case .ftp:
                if let url = urlFor(scheme: "ftp", host: host, port: port.number) {
                    return PortInteraction(accessibilityLabel: "Open FTP port \(port.number) on \(host)",
                                            action: .openURL(url))
                }
            case .ssh:
                let command = sshCommand(host: host, port: port.number)
                return PortInteraction(accessibilityLabel: "Copy SSH command for \(host)",
                                        action: .copy(command))
            case .smb:
                if let url = urlFor(scheme: "smb", host: host, port: port.number) {
                    return PortInteraction(accessibilityLabel: "Open SMB share on \(host)",
                                            action: .openURL(url))
                }
            case .vnc:
                if let url = urlFor(scheme: "vnc", host: host, port: port.number) {
                    return PortInteraction(accessibilityLabel: "Open VNC session to \(host)",
                                            action: .openURL(url))
                }
            case .telnet:
                let command = "telnet \(host) \(port.number)"
                return PortInteraction(accessibilityLabel: "Copy telnet command for \(host)",
                                        action: .copy(command))
            default:
                break
            }
        }

        let fallback = "\(host):\(port.number)"
        return PortInteraction(accessibilityLabel: "Copy \(fallback)",
                                action: .copy(fallback))
    }

    private func hostForPortAction() -> String? {
        if let hostname = device.hostname, !hostname.isEmpty { return hostname }
        if let ip = device.bestDisplayIP { return ip }
        if let primary = device.primaryIP { return primary }
        return nil
    }

    private func urlFor(scheme: String, host: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if shouldSpecifyPort(for: scheme, port: port) {
            components.port = port
        }
        return components.url
    }

    private func shouldSpecifyPort(for scheme: String, port: Int) -> Bool {
        switch scheme {
        case "http": return port != 80
        case "https": return port != 443
        case "ftp": return port != 21
        case "smb": return port != 445
        case "vnc": return port != 5900
        default: return true
        }
    }

    private func sshCommand(host: String, port: Int) -> String {
        if port == 22 { return "ssh \(host)" }
        return "ssh -p \(port) \(host)"
    }

    private func inferredServiceType(for port: Port) -> NetworkService.ServiceType? {
        if let mapped = ServiceDeriver.wellKnownPorts[port.number]?.0 {
            return mapped
        }

        let name = port.serviceName.lowercased()
        if name.contains("https") { return .https }
        if name.contains("http") { return .http }
        if name.contains("ssh") { return .ssh }
        if name.contains("ftp") { return .ftp }
        if name.contains("smb") || name.contains("cifs") { return .smb }
        if name.contains("vnc") || name.contains("rfb") { return .vnc }
        if name.contains("telnet") { return .telnet }
        if name.contains("ipp") { return .ipp }
        if name.contains("printer") { return .printer }
        return nil
    }
}


struct UnifiedDeviceDetail: View {
    private let inputDevice: Device
    @ObservedObject var settings: AppSettings
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel: DeviceDetailViewModel

    private var shouldShowFingerprints: Bool { settings.showFingerprints }

    private var device: Device { viewModel.device }

    init(device: Device, settings: AppSettings) {
        self.inputDevice = device
        self._settings = ObservedObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device))
    }

    private var allIPs: [String] {
        var result: [String] = []
        if let primary = device.primaryIP { result.append(primary) }
        let others = device.ips.filter { $0 != device.primaryIP }
        result.append(contentsOf: others.sorted())
        return result
    }

    private var discoverySources: [DiscoverySource] {
        device.discoverySources
            .filter { $0 != .unknown }
            .sorted { lhs, rhs in
                let ranking: [DiscoverySource] = [.arp, .ping, .mdns, .ssdp, .portScan, .httpProbe, .reverseDNS, .manual, .unknown]
                let li = ranking.firstIndex(of: lhs) ?? ranking.count
                let ri = ranking.firstIndex(of: rhs) ?? ranking.count
                if li == ri { return lhs.rawValue < rhs.rawValue }
                return li < ri
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space(.xxl)) {
                header
                overviewSection
                networkSection
                if !discoverySources.isEmpty { discoverySection }
                servicesSection
                portsSection
                if shouldShowFingerprints, let fingerprints = device.fingerprints, !fingerprints.isEmpty { fingerprintSection(fingerprints) }
            }
            .padding(Theme.space(.xl))
        }
        .background(Theme.color(.bgRoot).ignoresSafeArea())
        .navigationTitle("Device")
        .onChange(of: inputDevice) { _, newValue in
            viewModel.update(device: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.space(.lg)) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius(.xl))
                    .fill(Theme.color(.bgElevated))
                    .frame(width: 80, height: 80)
                Image(systemName: DeviceIconResolver.iconName(for: device))
                    .font(.system(size: 34))
                    .foregroundColor(Theme.color(.accentPrimary))
            }
            VStack(alignment: .leading, spacing: Theme.space(.sm)) {
                Text(primaryTitle)
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.color(.textPrimary))
                if let vendor = device.vendor, !vendor.isEmpty {
                    Text(vendor)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.color(.textSecondary))
                }
                if let host = device.hostname, !host.isEmpty {
                    Text(host)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.color(.textTertiary))
                }
                if let classification = device.classification {
                    VStack(alignment: .leading, spacing: Theme.space(.xxs)) {
                        Text(classification.formFactor?.rawValue.capitalized ?? "Unclassified")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.color(.textSecondary))
                        ConfidenceLevelView(confidence: classification.confidence)
                        if !classification.reason.isEmpty {
                            Text(classification.reason)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.color(.textTertiary))
                                .lineLimit(2)
                        }
                    }
                }
            }
            Spacer()
            Circle()
                .fill(device.isOnline ? Theme.color(.statusOnline) : Theme.color(.statusOffline))
                .frame(width: 18, height: 18)
                .shadow(color: device.isOnline ? Theme.color(.statusOnline).opacity(0.6) : .clear,
                        radius: 4,
                        y: 1)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            infoRow("Device ID", device.id)
            infoRow("Manufacturer", device.vendor)
            infoRow("Model Hint", device.modelHint)
            if let classification = device.classification {
                infoRow("Classification", classification.formFactor?.rawValue.capitalized)
                infoRow("Confidence", classification.confidence.rawValue.capitalized)
                infoRow("Reason", classification.reason)
            }
            infoRow("Status", device.isOnline ? "Online" : "Offline")
            infoRow("First Seen", formatted(device.firstSeen))
            infoRow("Last Seen", formatted(device.lastSeen))
        }
        .cardStyle()
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            infoRow("Primary IP", device.primaryIP)
            let secondary = Array(allIPs.dropFirst())
            if !secondary.isEmpty {
                VStack(alignment: .leading, spacing: Theme.space(.xxs)) {
                    Text("Other IPs")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.color(.textSecondary))
                    ForEach(secondary, id: \.self) { addr in
                        Text(addr)
                            .font(Theme.Typography.mono)
                            .foregroundColor(Theme.color(.textPrimary))
                    }
                }
            }
            infoRow("Hostname", device.hostname)
            infoRow("MAC", device.macAddress)
            if let rtt = device.rttMillis {
                infoRow("RTT", String(format: "%.1f ms", rtt))
            }
        }
        .cardStyle()
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            Text("Discovery Sources")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.color(.textSecondary))
            DiscoveryPillsView(sources: discoverySources)
        }
        .cardStyle()
    }

    private var servicesSection: some View {
        Group {
            if !device.displayServices.isEmpty {
                VStack(alignment: .leading, spacing: Theme.space(.sm)) {
                    Text("Services")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.color(.textSecondary))
                    ServiceTagsView(services: device.displayServices, device: device)
                }
                .cardStyle()
            }
        }
    }

    private var portsSection: some View {
        Group {
            if !device.openPorts.isEmpty {
                VStack(alignment: .leading, spacing: Theme.space(.md)) {
                    Text("Open Ports")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.color(.textSecondary))
                    VStack(spacing: Theme.space(.sm)) {
                        ForEach(device.openPorts) { port in
                            HStack(alignment: .center, spacing: Theme.space(.md)) {
                                VStack(alignment: .leading, spacing: Theme.space(.xxs)) {
                                    Text("\(port.number)/\(port.transport)")
                                        .font(Theme.Typography.mono)
                                        .foregroundColor(Theme.color(.textPrimary))
                                    Text(port.serviceName.isEmpty ? "Unknown" : port.serviceName)
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.color(.textSecondary))
                                }
                                Spacer()
                                portStatusView(for: port)
                            }
                            .padding(Theme.space(.md))
                            .background(Theme.color(.bgElevated))
                            .cornerRadius(Theme.radius(.md))
    }
}
                }
                .cardStyle()
            }
        }
    }

    private func fingerprintSection(_ fingerprints: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            Text("Fingerprints")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.color(.textSecondary))
            ForEach(fingerprints.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: Theme.space(.md)) {
                    Text(key)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.color(.textSecondary))
                        .frame(width: 120, alignment: .leading)
                    Text(fingerprints[key] ?? "")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.color(.textPrimary))
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: Theme.space(.md)) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
                .frame(width: 120, alignment: .leading)
            Text(value ?? "N/A")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.color(.textPrimary))
                .multilineTextAlignment(.leading)
        }
    }

    private var primaryTitle: String { device.name ?? device.vendor ?? device.hostname ?? device.bestDisplayIP ?? device.id }

    private func statusColor(_ status: Port.Status) -> Color {
        switch status {
        case .open: return Theme.color(.statusOnline)
        case .closed: return Theme.color(.textTertiary)
        case .filtered: return Theme.color(.accentWarn)
        }
    }

    @ViewBuilder
    private func portStatusView(for port: Port) -> some View {
        let label = port.status.rawValue.uppercased()
        let styledLabel = Text(label)
            .font(Theme.Typography.tag)
            .padding(.horizontal, Theme.space(.sm))
            .padding(.vertical, Theme.space(.xs))
            .background(statusColor(port.status).opacity(0.2))
            .foregroundColor(statusColor(port.status))
            .cornerRadius(Theme.radius(.sm))

        if let interaction = viewModel.interaction(for: port) {
            Button {
                handle(action: interaction.action)
            } label: {
                styledLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(interaction.accessibilityLabel)
        } else {
            styledLabel
        }
    }

    private func handle(action: DeviceDetailAction) {
        switch action {
        case .openURL(let url):
            openURL(url)
        case .copy(let value):
            copyToClipboard(value)
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

    private func formatted(_ date: Date?) -> String? {
        guard let date else { return nil }
        return detailDateFormatter.string(from: date)
    }

    private let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ConfidenceLevelView: View {
    let confidence: ClassificationConfidence

    private var confidenceLabel: String {
        switch confidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return "Unknown"
        }
    }

    private var fillFraction: CGFloat {
        switch confidence {
        case .high: return 1
        case .medium: return 2.0 / 3.0
        case .low: return 1.0 / 3.0
        case .unknown: return 0
        }
    }

    private var fillColor: Color {
        switch confidence {
        case .high: return Theme.color(.statusOnline)
        case .medium: return Theme.color(.accentWarn)
        case .low: return Theme.color(.accentDanger)
        case .unknown: return Theme.color(.accentMuted)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(.xxs)) {
            HStack(spacing: Theme.space(.xxs)) {
                Text("Confidence")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
                Text(confidenceLabel.uppercased())
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.color(.bgElevated))
                    Capsule()
                        .fill(fillColor)
                        .frame(width: geometry.size.width * fillFraction)
                }
            }
            .frame(height: 8)
            .accessibilityLabel("Confidence \(confidenceLabel)")
        }
    }
}

#if DEBUG
private extension Device {
    static var previewSample: Device {
        Device(primaryIP: "192.168.1.42",
               ips: ["192.168.1.42", "192.168.1.43"],
               hostname: "living-room-apple-tv",
               macAddress: "AA:BB:CC:DD:EE:FF",
               vendor: "Apple",
               modelHint: "AppleTV6,2",
               classification: Device.Classification(formFactor: .tv,
                                                      rawType: "apple_tv",
                                                      confidence: .high,
                                                      reason: "Fingerprint indicates Apple TV",
                                                      sources: ["fingerprint:model"]),
               discoverySources: [.mdns, .ping],
               services: [NetworkService(name: "AirPlay",
                                         type: .airplay,
                                         rawType: "_airplay._tcp",
                                         port: 7000,
                                         isStandardPort: true)],
               openPorts: [Port(number: 7000,
                                transport: "tcp",
                                serviceName: "airplay",
                                description: "AirPlay",
                                status: .open,
                                lastSeenOpen: Date())],
               fingerprints: ["model": "AppleTV6,2"],
               firstSeen: Date().addingTimeInterval(-7200),
               lastSeen: Date())
    }
}

struct UnifiedDeviceDetail_Previews: PreviewProvider {
    static var previews: some View {
        let settings = AppSettings()
        return UnifiedDeviceDetail(device: .previewSample, settings: settings)
            .frame(width: 420)
            .preferredColorScheme(.dark)
    }
}
#endif
