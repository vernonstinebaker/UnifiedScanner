import SwiftUI

struct DeviceDetailSheet: View {
    let device: Device
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            UnifiedDeviceDetail(device: device, settings: settings)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    LoggingService.debug("DeviceDetailSheet.onAppear device=\(device.id)", category: .general)
                }
        }
    }
}
