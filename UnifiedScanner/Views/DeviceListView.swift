import SwiftUI

struct DeviceListView: View {
    @ObservedObject var store: SnapshotService
    @Binding var selectedDeviceID: String?
    @Binding var sheetDeviceSnapshot: Device?
    let mode: LayoutMode

    enum LayoutMode {
        case compact, sidebar
    }

    var body: some View {
        switch mode {
        case .compact:
            deviceListCompact
        case .sidebar:
            sidebarList
        }
    }

    private var deviceListCompact: some View {
        List {
            ForEach(store.devices, id: \.id) { device in
                Button {
                    let currentCount = store.devices.count
                    LoggingService.debug("tap:first row device id=\(device.id) before selection count=\(currentCount)", category: .general)
                    selectedDeviceID = device.id
                    sheetDeviceSnapshot = device
                    LoggingService.debug("presenting sheet snapshot id=\(device.id)", category: .general)
                } label: {
                    DeviceRowView(device: device, isSelected: false)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Theme.color(.bgRoot))
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(Theme.color(.bgRoot))
        .padding(.bottom, Theme.space(.xxxl))
    }

    private var sidebarList: some View {
        List(selection: $selectedDeviceID) {
            ForEach(store.devices) { device in
                NavigationLink(value: device.id) {
                    DeviceRowView(device: device, isSelected: selectedDeviceID == device.id)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Theme.color(.bgRoot))
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(Theme.color(.bgRoot))
        .padding(.bottom, Theme.space(.xxxl))
    }
}
