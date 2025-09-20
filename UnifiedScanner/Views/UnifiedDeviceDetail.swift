import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct UnifiedDeviceDetail: View {
    let device: Device

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
                let ranking: [DiscoverySource] = [.arp, .ping, .mdns, .ssdp, .portScan, .reverseDNS, .manual, .unknown]
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
                if let fingerprints = device.fingerprints, !fingerprints.isEmpty { fingerprintSection(fingerprints) }
                servicesSection
                portsSection
            }
            .padding(Theme.space(.xl))
        }
        .background(Theme.color(.bgRoot).ignoresSafeArea())
        .navigationTitle("Device")
    }

    private var header: some View {
        HStack(spacing: Theme.space(.lg)) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius(.xl))
                    .fill(Theme.color(.bgElevated))
                    .frame(width: 80, height: 80)
                Image(systemName: iconName)
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
                    HStack(spacing: Theme.space(.sm)) {
                        ConfidenceBadge(confidence: classification.confidence)
                        Text(classification.formFactor?.rawValue.capitalized ?? "Unclassified")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.color(.textSecondary))
                    }
                    if !classification.reason.isEmpty {
                        Text(classification.reason)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.color(.textTertiary))
                            .lineLimit(2)
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
                    ServiceTagsView(services: device.displayServices)
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
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: Theme.space(.xxs)) {
                                    Text("\(port.number)/\(port.transport)")
                                        .font(Theme.Typography.mono)
                                        .foregroundColor(Theme.color(.textPrimary))
                                    Text(port.serviceName.isEmpty ? "Unknown" : port.serviceName)
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.color(.textSecondary))
                                }
                                Spacer()
                                Text(port.status.rawValue.uppercased())
                                    .font(Theme.Typography.tag)
                                    .padding(.horizontal, Theme.space(.sm))
                                    .padding(.vertical, Theme.space(.xs))
                                    .background(statusColor(port.status).opacity(0.2))
                                    .foregroundColor(statusColor(port.status))
                                    .cornerRadius(Theme.radius(.sm))
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

    private var primaryTitle: String { device.vendor ?? device.hostname ?? device.bestDisplayIP ?? device.id }

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

    private func statusColor(_ status: Port.Status) -> Color {
        switch status {
        case .open: return Theme.color(.statusOnline)
        case .closed: return Theme.color(.textTertiary)
        case .filtered: return Theme.color(.accentWarn)
        }
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

