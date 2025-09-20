import SwiftUI

/// Central design tokens adopted from the BonjourScanner/netscan design language.
/// Dark-first palette; light-mode variations can be introduced later.
enum Theme {
    enum ColorToken: String {
        case accentPrimary, accentSecondary, accentWarn, accentDanger, accentMuted
        case bgRoot, bgCard, bgElevated
        case separator
        case textPrimary, textSecondary, textTertiary
        case statusOnline, statusOffline
    }

    static func color(_ token: ColorToken) -> Color {
        switch token {
        case .accentPrimary: return Color(hex: "#1FF0A6")
        case .accentSecondary: return Color(hex: "#4A90E2")
        case .accentWarn: return Color.orange
        case .accentDanger: return Color.red
        case .accentMuted: return Color.gray.opacity(0.45)

        case .bgRoot: return Color(hex: "#151826")
        case .bgCard: return Color(hex: "#1F2234")
        case .bgElevated: return Color(hex: "#2C3050")

        case .separator: return Color.white.opacity(0.08)
        case .textPrimary: return Color.white
        case .textSecondary: return Color.white.opacity(0.75)
        case .textTertiary: return Color.white.opacity(0.55)

        case .statusOnline: return Color(hex: "#1FF0A6")
        case .statusOffline: return Color.red.opacity(0.7)
        }
    }

    enum Spacing: CGFloat { case xxs=2, xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32 }
    static func space(_ spacing: Spacing) -> CGFloat { spacing.rawValue }

    enum Radius: CGFloat { case xs=4, sm=8, md=12, lg=16, xl=24 }
    static func radius(_ radius: Radius) -> CGFloat { radius.rawValue }

    enum Typography {
        static var largeTitle: Font { .system(size: 32, weight: .bold, design: .rounded) }
        static var title: Font { .system(size: 24, weight: .semibold, design: .rounded) }
        static var headline: Font { .system(size: 18, weight: .semibold, design: .rounded) }
        static var body: Font { .system(size: 15, weight: .regular, design: .default) }
        static var subheadline: Font { .system(size: 14, weight: .medium, design: .rounded) }
        static var mono: Font { .system(size: 13, design: .monospaced) }
        static var caption: Font { .system(size: 12, weight: .medium, design: .rounded) }
        static var tag: Font { .system(size: 11, weight: .semibold, design: .rounded) }
    }

    struct ServiceStyle { let color: Color; let icon: String; let label: String }

    static func style(for service: NetworkService.ServiceType) -> ServiceStyle {
        switch service {
        case .http: return ServiceStyle(color: color(.accentSecondary), icon: "globe", label: "HTTP")
        case .https: return ServiceStyle(color: color(.accentSecondary), icon: "lock", label: "HTTPS")
        case .ssh: return ServiceStyle(color: color(.accentSecondary), icon: "terminal", label: "SSH")
        case .dns: return ServiceStyle(color: color(.accentSecondary), icon: "network", label: "DNS")
        case .dhcp: return ServiceStyle(color: color(.accentSecondary), icon: "arrow.triangle.2.circlepath", label: "DHCP")
        case .smb: return ServiceStyle(color: color(.accentSecondary), icon: "externaldrive.connected.to.line.below", label: "SMB")
        case .ftp: return ServiceStyle(color: color(.accentSecondary), icon: "tray.and.arrow.down", label: "FTP")
        case .vnc: return ServiceStyle(color: color(.accentSecondary), icon: "display", label: "VNC")
        case .airplay: return ServiceStyle(color: color(.accentSecondary), icon: "airplayvideo", label: "AirPlay")
        case .airplayAudio: return ServiceStyle(color: color(.accentSecondary), icon: "hifispeaker", label: "AirPlay")
        case .homekit: return ServiceStyle(color: color(.accentSecondary), icon: "house", label: "HomeKit")
        case .chromecast: return ServiceStyle(color: color(.accentSecondary), icon: "tv.badge.wifi", label: "Cast")
        case .spotify: return ServiceStyle(color: color(.accentSecondary), icon: "music.note", label: "Spotify")
        case .printer, .ipp: return ServiceStyle(color: color(.accentSecondary), icon: "printer", label: "Print")
        case .telnet: return ServiceStyle(color: color(.accentSecondary), icon: "chevron.left.slash.chevron.right", label: "Telnet")
        case .other: return ServiceStyle(color: color(.accentMuted), icon: "questionmark", label: "Service")
        }
    }

    static func discoveryStyle(for source: DiscoverySource) -> (title: String, color: Color) {
        switch source {
        case .arp: return ("ARP", color(.accentPrimary))
        case .ping: return ("PING", color(.accentSecondary))
        case .mdns: return ("MDNS", color(.accentPrimary))
        case .ssdp: return ("SSDP", color(.accentSecondary))
        case .portScan: return ("SCAN", color(.accentWarn))
        case .reverseDNS: return ("RDNS", color(.accentMuted))
        case .manual: return ("MANUAL", color(.accentMuted))
        case .unknown: return ("UNKNOWN", color(.accentMuted))
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.space(.lg))
            .background(Theme.color(.bgCard))
            .cornerRadius(Theme.radius(.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius(.lg), style: .continuous)
                    .stroke(Theme.color(.separator), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
