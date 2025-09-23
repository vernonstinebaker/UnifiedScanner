import SwiftUI

struct StatusSectionView: View {
    @ObservedObject var progress: ScanProgress
    @ObservedObject var networkInfo: NetworkInfoService
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            networkStatusHeader
            progressSection
        }
    }

    private var networkStatusHeader: some View {
        VStack(alignment: .leading, spacing: Theme.space(.xs)) {
            HStack(spacing: Theme.space(.lg)) {
                statusIcon(icon: "globe", value: networkInfo.networkDescription, usesMono: true)
                statusIcon(icon: "dot.radiowaves.left.and.right", value: networkInfo.ipDescription, usesMono: true)
                statusIcon(icon: "wifi", value: networkInfo.wifiDisplay, usesMono: false)
            }
            if settings.showInterface, let interface = networkInfo.interface {
                Text("Interface: \(interface.name)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textTertiary))
            }
        }
        .cardStyle()
    }

    private func statusIcon(icon: String, value: String, usesMono: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.space(.xs)) {
            Image(systemName: icon)
                .foregroundColor(Theme.color(.accentPrimary))
                .font(.system(size: 16, weight: .semibold))
            Text(value)
                .font(usesMono ? Theme.Typography.mono : Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
                .lineLimit(1)
        }
    }

    private var progressSection: some View {
        Group {
            if progress.started && !progress.finished {
                VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                    ProgressView(value: Double(progress.completedHosts), total: Double(max(progress.totalHosts, 1)))
                        .tint(Theme.color(.accentPrimary))
                    HStack(spacing: Theme.space(.sm)) {
                        Text(progressText)
                        Text("\(progress.successHosts) responsive")
                            .foregroundColor(Theme.color(.textSecondary))
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
                }
            } else if progress.phase == .arpPriming {
                indeterminateProgress("Priming ARP table…")
            } else if progress.phase == .enumerating {
                indeterminateProgress("Enumerating subnet…")
            } else if progress.phase == .arpRefresh && !progress.finished {
                indeterminateProgress("Refreshing ARP entries…")
            } else if progress.finished {
                Text("Scan complete: \(progress.successHosts) responsive hosts")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textSecondary))
            }
        }
    }

    private var progressText: String {
        switch progress.phase {
        case .pinging: return "Pinging \(progress.completedHosts)/\(progress.totalHosts) hosts"
        case .mdnsWarmup: return "Warming up mDNS…"
        default: return "Scanning \(progress.completedHosts)/\(progress.totalHosts) hosts"
        }
    }

    private func indeterminateProgress(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(.xs)) {
            ProgressView().tint(Theme.color(.accentPrimary))
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
        }
    }
}
