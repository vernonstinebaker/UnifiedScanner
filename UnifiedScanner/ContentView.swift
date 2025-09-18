//
//  ContentView.swift
//  UnifiedScanner
//
//  Created by Vernon Stinebaker on 9/18/25.
//

import SwiftUI
import ScannerUI
import ScannerDesign

struct ContentView: View {
    struct DeviceItem: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String?
        let detail: String?
        let isOnline: Bool
        let manufacturer: String?
        let ips: [String]
        let mac: String?
        let services: [ServiceItem]
        let openPorts: [PortItem]
        let rttMs: Double?
        let hostname: String?
    }

    @State private var devices: [DeviceItem] = [
        DeviceItem(id: "1", title: "iPhone 15", subtitle: "Personal", detail: "192.168.1.2", isOnline: true, manufacturer: "Apple", ips: ["192.168.1.2"], mac: "AA:BB:CC:DD:EE:01", services: [ServiceItem(name: "device.local", port: 80, protocolName: "http")], openPorts: [PortItem(port: 22, proto: "tcp", state: "open")], rttMs: 12.3, hostname: "iphone.local"),
        DeviceItem(id: "2", title: "MacBook Pro", subtitle: "Work", detail: "192.168.1.3", isOnline: true, manufacturer: "Apple", ips: ["192.168.1.3"], mac: "AA:BB:CC:DD:EE:02", services: [ServiceItem(name: "mbp.local", port: 22, protocolName: "ssh")], openPorts: [PortItem(port: 22, proto: "tcp", state: "open"), PortItem(port: 80, proto: "tcp", state: "open")], rttMs: 7.8, hostname: "macbook.local"),
        DeviceItem(id: "3", title: "Chromecast", subtitle: "Living Room", detail: "192.168.1.5", isOnline: false, manufacturer: "Google", ips: ["192.168.1.5"], mac: "AA:BB:CC:DD:EE:03", services: [], openPorts: [], rttMs: nil, hostname: "chromecast.local")
    ]

    @State private var selectedID: String? = nil
    @State private var showDetailSheet: Bool = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isCompact {
                NavigationStack {
                    List(devices) { device in
                        Button {
                            selectedID = device.id
                            showDetailSheet = true
                        } label: {
                            DeviceRow(id: device.id,
                                      title: device.title,
                                      subtitle: device.subtitle,
                                      detail: device.detail,
                                      isOnline: device.isOnline)
                        }
                        .buttonStyle(.plain)
                    }
                    .navigationTitle("Devices")
                            .sheet(isPresented: $showDetailSheet) {
                        if let id = selectedID, let device = devices.first(where: { $0.id == id }) {
                            NavigationStack {
                                UnifiedDeviceDetail(title: device.title,
                                                    manufacturer: device.manufacturer,
                                                    ips: device.ips,
                                                    mac: device.mac,
                                                    isOnline: device.isOnline,
                                                    services: device.services,
                                                    openPorts: device.openPorts,
                                                    rttMs: device.rttMs,
                                                    hostname: device.hostname)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Done") { showDetailSheet = false }
                                        }
                                    }
                            }
                        } else {
                            EmptyView()
                        }
                    }
                }
                .background(ScannerTheme.color(.bgRoot).ignoresSafeArea())
            } else {
                NavigationSplitView {
                    List(selection: $selectedID) {
                        ForEach(devices) { device in
                            NavigationLink(destination:
                                            UnifiedDeviceDetail(title: device.title,
                                                                manufacturer: device.manufacturer,
                                                                ips: device.ips,
                                                                mac: device.mac,
                                                                isOnline: device.isOnline,
                                                                services: device.services,
                                                                openPorts: device.openPorts,
                                                                rttMs: device.rttMs,
                                                                hostname: device.hostname),
                                           tag: device.id,
                                           selection: $selectedID) {
                                DeviceRow(id: device.id,
                                          title: device.title,
                                          subtitle: device.subtitle,
                                          detail: device.detail,
                                          isOnline: device.isOnline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.inset)
                    .navigationTitle("Devices")
                } detail: {
                    if let id = selectedID, let device = devices.first(where: { $0.id == id }) {
                        UnifiedDeviceDetail(title: device.title,
                                            manufacturer: device.manufacturer,
                                            ips: device.ips,
                                            mac: device.mac,
                                            isOnline: device.isOnline,
                                            services: device.services,
                                            openPorts: device.openPorts,
                                            rttMs: device.rttMs,
                                            hostname: device.hostname)
                    } else {
                        VStack {
                            Text("Select a device")
                                .font(ScannerTheme.Typography.headline)
                                .foregroundColor(ScannerTheme.color(.textSecondary))
                        }
                    }
                }
                .background(ScannerTheme.color(.bgRoot).ignoresSafeArea())
            }
        }
    }
}

#Preview {
    ContentView()
}
