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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                networkInfo
                servicesSection
                portsSection
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle("Device")
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: iconName)
                    .font(.system(size: 30))
                    .foregroundColor(.accentColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(primaryTitle)
                    .font(.title3.weight(.semibold))
                if let vendor = device.vendor { Text(vendor).font(.subheadline).foregroundStyle(.secondary) }
                if let host = device.hostname { Text(host).font(.caption).foregroundStyle(.secondary) }
                if let c = device.classification {
                    HStack(spacing: 6) {
                        ConfidenceBadge(confidence: c.confidence)
                        Text(c.formFactor?.rawValue.capitalized ?? "Unclassified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !c.reason.isEmpty {
                        Text(c.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer()
            Circle()
                .fill(device.isOnline ? Color.green : Color.red.opacity(0.8))
                .frame(width: 16, height: 16)
        }
    }

    private var networkInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("Primary IP", device.primaryIP)
            let secondary = Array(allIPs.dropFirst())
            infoRow("Other IPs", secondary.isEmpty ? nil : secondary.joined(separator: ", "))
            infoRow("MAC", device.macAddress)
            if let rtt = device.rttMillis { infoRow("RTT (ms)", String(format: "%.1f", rtt)) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
    }

    private var servicesSection: some View {
        Group {
            if !device.displayServices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Services").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(device.displayServices) { svc in
                                Button { openService(svc) } label: {
                                    HStack(spacing: 4) {
                                        Text(serviceLabel(svc))
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.15)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var portsSection: some View {
        Group {
            if !device.openPorts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open Ports").font(.headline)
                    VStack(spacing: 8) {
                        ForEach(device.openPorts) { port in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(port.number)/\(port.transport)")
                                        .font(.system(.subheadline, design: .monospaced))
                                    Text(port.serviceName.isEmpty ? "Unknown" : port.serviceName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(port.status.rawValue.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(statusColor(port.status).opacity(0.15))
                                    .foregroundStyle(statusColor(port.status))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "N/A").font(.subheadline)
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
        if device.displayServices.contains(where: { $0.type == .airplay }) { return "airplayvideo" }
        if device.displayServices.contains(where: { $0.type == .printer }) { return "printer" }
        if device.displayServices.contains(where: { $0.type == .http || $0.type == .https }) { return "server.rack" }
        return "desktopcomputer"
    }

    private func statusColor(_ status: Port.Status) -> Color {
        switch status {
        case .open: return .green
        case .closed: return .gray
        case .filtered: return .orange
        }
    }

    private func serviceLabel(_ svc: NetworkService) -> String {
        if let p = svc.port { return "\(svc.name):\(p)" }
        return svc.name
    }

    private func openService(_ svc: NetworkService) {
        guard let port = svc.port else { return }
        switch svc.type {
        case .http, .https:
            let scheme = (svc.type == .https) ? "https" : "http"
            if let host = device.bestDisplayIP ?? device.hostname, let url = URL(string: "\(scheme)://\(host):\(port)") {
                #if canImport(UIKit)
                UIApplication.shared.open(url)
                #elseif canImport(AppKit)
                NSWorkspace.shared.open(url)
                #endif
            }
        case .ssh:
            if let host = device.bestDisplayIP ?? device.hostname {
                let cmd = "ssh user@\(host) -p \(port)"
                #if canImport(UIKit)
                UIPasteboard.general.string = cmd
                #elseif canImport(AppKit)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(cmd, forType: .string)
                #endif
            }
        default:
            break
        }
    }
}

#Preview("Detail") {
    UnifiedDeviceDetail(device: .mockMac)
}
