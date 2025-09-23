import SwiftUI

struct SummaryFooterView: View {
    let deviceCount: Int
    let onlineCount: Int
    let serviceCount: Int

    var body: some View {
        HStack {
            StatBlock(count: deviceCount, title: "Devices")
            Spacer()
            StatBlock(count: onlineCount, title: "Online")
            Spacer()
            StatBlock(count: serviceCount, title: "Services")
        }
        .padding(.horizontal, Theme.space(.xl))
        .padding(.vertical, Theme.space(.lg))
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.radius(.xl))
    }
}

struct StatBlock: View {
    let count: Int
    let title: String

    var body: some View {
        VStack(spacing: Theme.space(.xs)) {
            Text("\(count)")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.color(.accentPrimary))
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
        }
    }
}
