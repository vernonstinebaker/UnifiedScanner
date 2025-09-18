import Foundation

public extension Device {
    static var mockRouter: Device {
        Device(primaryIP: "192.168.1.1",
               ips: ["192.168.1.1"],
               hostname: "router.local",
               macAddress: "AA:BB:CC:DD:EE:01",
               vendor: "Ubiquiti",
               discoverySources: [.arp, .ping],
               services: [ServiceDeriver.makeService(fromRaw: "_http._tcp", port: 80)],
               openPorts: [Port(number: 80, serviceName: "http", description: "Web Admin", status: .open, lastSeenOpen: Date())],
               firstSeen: Date().addingTimeInterval(-86400),
               lastSeen: Date())
    }
    static var mockMac: Device {
        Device(primaryIP: "192.168.1.23",
               ips: ["192.168.1.23"],
               hostname: "macbook-pro.local",
               macAddress: "AA:BB:CC:DD:EE:02",
               vendor: "Apple",
               discoverySources: [.mdns, .arp, .ping],
               services: [ServiceDeriver.makeService(fromRaw: "_ssh._tcp", port: 22), ServiceDeriver.makeService(fromRaw: "_airplay._tcp", port: 7000)],
               openPorts: [Port(number: 22, serviceName: "ssh", description: "Remote Login", status: .open, lastSeenOpen: Date())],
               firstSeen: Date().addingTimeInterval(-7200),
               lastSeen: Date())
    }
    static var mockAppleTV: Device {
        Device(primaryIP: "192.168.1.40",
               ips: ["192.168.1.40"],
               hostname: "Apple-TV.local",
               macAddress: "AA:BB:CC:DD:EE:03",
               vendor: "Apple",
               discoverySources: [.mdns],
               services: [ServiceDeriver.makeService(fromRaw: "_airplay._tcp", port: 7000)],
               openPorts: [],
               firstSeen: Date().addingTimeInterval(-36000),
               lastSeen: Date())
    }
    static var mockPrinter: Device {
        Device(primaryIP: "192.168.1.55",
               ips: ["192.168.1.55"],
               hostname: "OfficePrinter.local",
               macAddress: "AA:BB:CC:DD:EE:04",
               vendor: "HP",
               discoverySources: [.mdns, .arp],
               services: [ServiceDeriver.makeService(fromRaw: "_ipp._tcp", port: 631)],
               openPorts: [Port(number: 631, serviceName: "ipp", description: "IPP Printing", status: .open, lastSeenOpen: Date())],
               firstSeen: Date().addingTimeInterval(-54000),
               lastSeen: Date())
    }
    static var mockIOT: Device {
        Device(primaryIP: "192.168.1.70",
               ips: ["192.168.1.70"],
               hostname: "plug-1.local",
               macAddress: "AA:BB:CC:DD:EE:05",
               vendor: "TP-Link",
               discoverySources: [.arp, .ping],
               services: [],
               openPorts: [Port(number: 80, serviceName: "http", description: "Embedded UI", status: .open, lastSeenOpen: Date())],
               firstSeen: Date().addingTimeInterval(-10800),
               lastSeen: Date())
    }
    static var allMocks: [Device] { [mockRouter, mockMac, mockAppleTV, mockPrinter, mockIOT] }
}
