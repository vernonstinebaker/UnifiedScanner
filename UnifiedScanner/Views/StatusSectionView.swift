import SwiftUI
import Combine

@MainActor
final class StatusDashboardViewModel: ObservableObject {
    struct StatusItem: Identifiable, Equatable {
        let id: String
        let icon: String
        let value: String
        let usesMono: Bool
    }

    enum ProgressState: Equatable {
        case idle
        case indeterminate(label: String)
        case determinate(current: Int, total: Int, caption: String, responsiveSummary: String)
        case completed(message: String)
    }

    @Published private(set) var statusItems: [StatusItem] = []
    @Published private(set) var interfaceLine: String?
    @Published private(set) var showInterfaceLine: Bool = false
    @Published private(set) var progressState: ProgressState = .idle

    private let progress: ScanProgress
    private let networkProvider: any NetworkStatusProviding
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []

    init(progress: ScanProgress,
         networkProvider: any NetworkStatusProviding,
         settings: AppSettings) {
        self.progress = progress
        self.networkProvider = networkProvider
        self.settings = settings
        bind()
        recompute()
    }

    func refreshNetwork() {
        networkProvider.refresh()
    }

    private func bind() {
        progress.objectWillChange
            .sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)

        networkProvider.objectWillChange
            .sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in self?.scheduleRecompute() }
            .store(in: &cancellables)
    }

    private func scheduleRecompute() {
        Task { @MainActor [weak self] in
            self?.recompute()
        }
    }

    private func recompute() {
        statusItems = [
            StatusItem(id: "network", icon: "globe", value: networkProvider.networkDescription, usesMono: true),
            StatusItem(id: "ip", icon: "dot.radiowaves.left.and.right", value: networkProvider.ipDescription, usesMono: true),
            StatusItem(id: "wifi", icon: "wifi", value: networkProvider.wifiDisplay, usesMono: false)
        ]

        if settings.showInterface, let interface = networkProvider.interface {
            interfaceLine = "Interface: \(interface.name)"
            showInterfaceLine = true
        } else {
            interfaceLine = nil
            showInterfaceLine = false
        }

        progressState = computeProgressState()
    }

    private func computeProgressState() -> ProgressState {
        if progress.finished {
            return .completed(message: "Scan complete: \(progress.successHosts) responsive hosts")
        }

        if progress.started && !progress.finished && progress.totalHosts > 0 {
            return determinateState()
        }

        switch progress.phase {
        case .idle:
            return .idle
        case .arpPriming:
            return .indeterminate(label: "Priming ARP table…")
        case .enumerating:
            return .indeterminate(label: "Enumerating subnet…")
        case .arpRefresh:
            return .indeterminate(label: "Refreshing ARP entries…")
        case .mdnsWarmup:
            return .indeterminate(label: "Warming up mDNS…")
        case .pinging:
            return progress.totalHosts > 0 ? determinateState() : .indeterminate(label: "Pinging hosts…")
        case .complete:
            return .completed(message: "Scan complete: \(progress.successHosts) responsive hosts")
        }
    }

    private func determinateState() -> ProgressState {
        let caption: String
        switch progress.phase {
        case .pinging:
            caption = "Pinging \(progress.completedHosts)/\(progress.totalHosts) hosts"
        case .mdnsWarmup:
            caption = "Warming up mDNS…"
        default:
            caption = "Scanning \(progress.completedHosts)/\(progress.totalHosts) hosts"
        }
        let responsive = "\(progress.successHosts) responsive"
        return .determinate(current: progress.completedHosts,
                             total: progress.totalHosts,
                             caption: caption,
                             responsiveSummary: responsive)
    }
}


struct StatusSectionView: View {
    @ObservedObject var viewModel: StatusDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            networkStatusHeader
            progressSection
        }
    }

    private var networkStatusHeader: some View {
        VStack(alignment: .leading, spacing: Theme.space(.xs)) {
            HStack(spacing: Theme.space(.lg)) {
                ForEach(viewModel.statusItems) { item in
                    statusIcon(icon: item.icon, value: item.value, usesMono: item.usesMono)
                }
            }
            if viewModel.showInterfaceLine, let line = viewModel.interfaceLine {
                Text(line)
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

    @ViewBuilder
    private var progressSection: some View {
        switch viewModel.progressState {
        case .idle:
            EmptyView()
        case .indeterminate(let label):
            indeterminateProgress(label)
        case .determinate(let current, let total, let caption, let responsiveSummary):
            VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .tint(Theme.color(.accentPrimary))
                HStack(spacing: Theme.space(.sm)) {
                    Text(caption)
                    Text(responsiveSummary)
                        .foregroundColor(Theme.color(.textSecondary))
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
            }
        case .completed(let message):
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
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

#if DEBUG
private final class PreviewStatusProvider: NetworkStatusProviding {
    let objectWillChange = ObservableObjectPublisher()

    var networkDescription: String = "192.168.1.0/24"
    var ipDescription: String = "192.168.1.20"
    var wifiDisplay: String = "Preview Wi-Fi"
    var interface: NetworkInterfaceDetails? = nil

    func refresh() { }
}

extension StatusDashboardViewModel {
    static func previewModel() -> StatusDashboardViewModel {
        let progress = ScanProgress()
        progress.phase = .pinging
        progress.totalHosts = 24
        progress.completedHosts = 12
        progress.successHosts = 8
        progress.started = true
        progress.finished = false

        let settings = AppSettings()
        settings.showInterface = false

        let provider = PreviewStatusProvider()
        return StatusDashboardViewModel(progress: progress,
                                        networkProvider: provider,
                                        settings: settings)
    }
}

struct StatusSectionView_Previews: PreviewProvider {
    static var previews: some View {
        StatusSectionView(viewModel: .previewModel())
            .padding()
            .background(Theme.color(.bgRoot))
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
    }
}
#endif
