import SwiftUI

struct DeviceRowView: View {
    let device: Device

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if let classification = device.classification {
                        ConfidenceBadge(confidence: classification.confidence)
                    }
                    if let vendor = device.vendor {
                        Text(vendor)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.red.opacity(0.7))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(device.isOnline ? "Online" : "Offline")
                }
                HStack(spacing: 8) {
                    if let ip = device.bestDisplayIP {
                        Text(ip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let mac = device.macAddress {
                        Text(mac)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospaced()
                    }
                    if let host = device.hostname, host != primaryTitle {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !device.displayServices.isEmpty {
                        Text(servicesSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .contentShape(Rectangle())
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
        // Fallback heuristics
        if device.displayServices.contains(where: { $0.type == .airplay }) { return "airplayvideo" }
        if device.displayServices.contains(where: { $0.type == .printer }) { return "printer" }
        if device.displayServices.contains(where: { $0.type == .http || $0.type == .https }) { return "server.rack" }
        return "desktopcomputer"
    }
    private var iconColor: Color {
        if device.isOnline { return .accentColor } else { return .secondary }
    }
    private var servicesSummary: String {
        let svc = device.displayServices
        if svc.isEmpty { return "" }
        if svc.count <= 2 {
            return svc.compactMap { $0.port.map { "\($0)" } ?? $0.name }.joined(separator: ", ")
        }
        return "\(svc.count) services"
    }
}

struct ConfidenceBadge: View {
    let confidence: ClassificationConfidence
    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Confidence \(label)")
    }
    private var label: String {
        switch confidence { case .high: return "HIGH"; case .medium: return "MED"; case .low: return "LOW"; case .unknown: return "?" }
    }
    private var color: Color {
        switch confidence { case .high: return .green; case .medium: return .orange; case .low: return .red; case .unknown: return .gray }
    }
}


