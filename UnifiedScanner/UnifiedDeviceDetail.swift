import SwiftUI
import ScannerDesign

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ServiceItem: Identifiable, Hashable {
    let id = UUID().uuidString
    let name: String
    let port: Int
    let protocolName: String
}

struct PortItem: Identifiable, Hashable {
    let id = UUID().uuidString
    let port: Int
    let proto: String
    let state: String
}

struct UnifiedDeviceDetail: View {
    let title: String
    let manufacturer: String?
    let ips: [String]
    let mac: String?
    let isOnline: Bool
    let services: [ServiceItem]
    let openPorts: [PortItem]
    let rttMs: Double?
    let hostname: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScannerTheme.space(.xl)) {
                // Header
                HStack(spacing: ScannerTheme.space(.md)) {
                    ZStack {
                        RoundedRectangle(cornerRadius: ScannerTheme.radius(.md))
                            .fill(ScannerTheme.color(.bgElevated))
                            .frame(width: 72, height: 72)
                        Image(systemName: "desktopcomputer")
                            .foregroundColor(ScannerTheme.color(.accentPrimary))
                            .font(.system(size: 28))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(ScannerTheme.Typography.title)
                            .foregroundColor(ScannerTheme.color(.textPrimary))
                        if let m = manufacturer {
                            Text(m)
                                .font(ScannerTheme.Typography.subheadline)
                                .foregroundColor(ScannerTheme.color(.textSecondary))
                        }
                        if let h = hostname {
                            Text(h)
                                .font(ScannerTheme.Typography.caption)
                                .foregroundColor(ScannerTheme.color(.textTertiary))
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(isOnline ? ScannerTheme.color(.statusOnline) : ScannerTheme.color(.statusOffline))
                        .frame(width: 14, height: 14)
                }

                // Network info card
                VStack(alignment: .leading, spacing: ScannerTheme.space(.md)) {
                    InfoRow(label: "Primary IP", value: ips.first)
                    InfoRow(label: "Other IPs", value: ips.dropFirst().joined(separator: ", ").isEmpty ? nil : ips.dropFirst().joined(separator: ", "))
                    InfoRow(label: "MAC", value: mac)
                    InfoRow(label: "RTT (ms)", value: rttMs.map { String(format: "%.1f", $0) })
                }
                .padding(ScannerTheme.space(.md))
                .background(ScannerTheme.color(.bgCard))
                .cornerRadius(ScannerTheme.radius(.md))

                // Services
                if !services.isEmpty {
                    VStack(alignment: .leading, spacing: ScannerTheme.space(.sm)) {
                        Text("Services")
                            .font(ScannerTheme.Typography.headline)
                            .foregroundColor(ScannerTheme.color(.textPrimary))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: ScannerTheme.space(.sm)) {
                                ForEach(services) { s in
                                    Button {
                                        openService(s)
                                    } label: {
                                        Text("\(s.name):\(s.port)")
                                            .font(ScannerTheme.Typography.caption)
                                            .foregroundColor(ScannerTheme.color(.textPrimary))
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(ScannerTheme.color(.bgElevated))
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                    }
                }

                // Open ports
                if !openPorts.isEmpty {
                    VStack(alignment: .leading, spacing: ScannerTheme.space(.sm)) {
                        Text("Open Ports")
                            .font(ScannerTheme.Typography.headline)
                            .foregroundColor(ScannerTheme.color(.textPrimary))
                        VStack(spacing: ScannerTheme.space(.sm)) {
                            ForEach(openPorts) { p in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("")
                                            .font(ScannerTheme.Typography.subheadline)
                                        Text("")
                                            .font(ScannerTheme.Typography.body)
                                    }
                                    Spacer()
                                    Text("\(p.port)/\(p.proto)")
                                        .font(ScannerTheme.Typography.mono)
                                        .foregroundColor(ScannerTheme.color(.textTertiary))
                                }
                                .padding(ScannerTheme.space(.md))
                                .background(ScannerTheme.color(.bgCard))
                                .cornerRadius(ScannerTheme.radius(.sm))
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(ScannerTheme.space(.lg))
        }
        .navigationTitle("Device")
    }

    func openService(_ s: ServiceItem) {
        // Attempt to open common service types
        if s.protocolName.lowercased().contains("http") {
            let urlString = "http://\(s.name):\(s.port)"
            if let url = URL(string: urlString) {
                #if canImport(UIKit)
                UIApplication.shared.open(url)
                #elseif canImport(AppKit)
                NSWorkspace.shared.open(url)
                #endif
            }
        } else if s.protocolName.lowercased().contains("ssh") {
            let cmd = "ssh user@\(s.name) -p \(s.port)"
            #if canImport(UIKit)
            UIPasteboard.general.string = cmd
            #elseif canImport(AppKit)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(cmd, forType: .string)
            #endif
        }
    }
}

fileprivate struct InfoRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack {
            Text(label).font(ScannerTheme.Typography.subheadline).foregroundColor(ScannerTheme.color(.textSecondary))
            Spacer()
            Text(value ?? "N/A").font(ScannerTheme.Typography.body).foregroundColor(ScannerTheme.color(.textPrimary))
        }
    }
}

struct UnifiedDeviceDetail_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedDeviceDetail(title: "My Device", manufacturer: "ACME", ips: ["192.168.1.2", "10.0.0.5"], mac: "AA:BB:CC:DD:EE:FF", isOnline: true, services: [ServiceItem(name: "http-device.local", port: 80, protocolName: "http")], openPorts: [PortItem(port: 22, proto: "tcp", state: "open")], rttMs: 12.4, hostname: "device.local")
    }
}
