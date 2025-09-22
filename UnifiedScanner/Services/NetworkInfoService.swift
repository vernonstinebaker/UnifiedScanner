import Foundation
import Combine
#if os(iOS) || os(macOS)
import CoreLocation
#endif
#if os(iOS)
import SystemConfiguration.CaptiveNetwork
import NetworkExtension
#elseif os(macOS)
import CoreWLAN
#endif

struct NetworkInterfaceDetails: Equatable {
    let name: String
    let ipAddress: String
    let netmask: String
    let prefix: Int
    let networkAddress: String
    let broadcastAddress: String
    fileprivate let ipRaw: UInt32
    fileprivate let netmaskRaw: UInt32

    var cidrDescription: String { "\(networkAddress)/\(prefix)" }
    var networkAddressOnly: String { networkAddress }

    var isPrivateIPv4: Bool {
        let value = ipRaw
        if (value & 0xFF00_0000) == 0x0A00_0000 { return true }
        if (value & 0xFFF0_0000) == 0xAC10_0000 { return true }
        if (value & 0xFFFF_0000) == 0xC0A8_0000 { return true }
        return false
    }
}

enum NetworkInterfaceResolver {
    static func primaryIPv4Interface() -> NetworkInterfaceDetails? {
        let interfaces = collectInterfaces()
        guard !interfaces.isEmpty else { return nil }

        var candidateNames = preferredInterfaceNames()
        for detail in interfaces where !candidateNames.contains(detail.name) {
            candidateNames.append(detail.name)
        }

        let grouped = Dictionary(grouping: interfaces, by: { $0.name })
        for name in candidateNames {
            guard let matches = grouped[name] else { continue }
            if let privateMatch = matches.first(where: { $0.isPrivateIPv4 }) {
                return privateMatch
            }
            if let first = matches.first {
                return first
            }
        }

        if let privateFallback = interfaces.first(where: { $0.isPrivateIPv4 }) {
            return privateFallback
        }

        return interfaces.first
    }

    private static func collectInterfaces() -> [NetworkInterfaceDetails] {
        var details: [NetworkInterfaceDetails] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return details }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = start
        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }
            guard let addrPtr = current.ifa_addr, let maskPtr = current.ifa_netmask else { continue }
            let flags = Int32(current.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP else { continue }
            guard (flags & IFF_LOOPBACK) != IFF_LOOPBACK else { continue }
            guard addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let ifName = decodeCString(current.ifa_name, context: "NetworkInterfaceResolver.ifname") ?? ""
            let disallowed = ["pdp", "ipsec", "utun", "lo", "gif", "awdl"]
            guard !disallowed.contains(where: { ifName.hasPrefix($0) }) else { continue }

            var addrIn = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var maskIn = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }

            var addrBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var maskBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addrIn.sin_addr, &addrBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            guard inet_ntop(AF_INET, &maskIn.sin_addr, &maskBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }

            let ipString = String(bytes: addrBuffer.map { UInt8($0) }, encoding: .utf8) ?? ""
            guard !ipString.hasPrefix("169.254.") else { continue }
            let netmaskString = String(bytes: maskBuffer.map { UInt8($0) }, encoding: .utf8) ?? ""
            guard let ipRaw = IPv4Parser.addressToUInt32(ipString),
                  let maskRaw = IPv4Parser.addressToUInt32(netmaskString) else { continue }

            let networkRaw = ipRaw & maskRaw
            let broadcastRaw = networkRaw | (UInt32.max ^ maskRaw)
            let prefix = maskRaw == 0 ? 0 : maskRaw.nonzeroBitCount
            let network = IPv4Parser.uint32ToAddress(networkRaw)
            let broadcast = IPv4Parser.uint32ToAddress(broadcastRaw)

            let detail = NetworkInterfaceDetails(name: ifName,
                                                 ipAddress: ipString,
                                                 netmask: netmaskString,
                                                 prefix: prefix,
                                                 networkAddress: network,
                                                 broadcastAddress: broadcast,
                                                 ipRaw: ipRaw,
                                                 netmaskRaw: maskRaw)
            details.append(detail)
        }

        return details
    }

    private static func preferredInterfaceNames() -> [String] {
        var names: [String] = []
#if os(iOS)
        names = ["en0", "en1", "en2", "bridge0"]
#elseif os(macOS)
        if let primary = CWWiFiClient.shared().interface()?.interfaceName {
            names.append(primary)
        }
        if let interfaces = CWWiFiClient.shared().interfaces() {
            for interface in interfaces {
                if let name = interface.interfaceName {
                    names.append(name)
                }
            }
        }
        names.append(contentsOf: ["en0", "en1", "en2", "bridge0"])
#endif
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

@MainActor
final class NetworkInfoService: NSObject, ObservableObject {
    @Published private(set) var interface: NetworkInterfaceDetails?
    @Published private(set) var wifiDisplay: String = "—"

#if os(iOS)
    private var locationManager: CLLocationManager?
    private var isLocationPermissionGranted = false
#endif

    override init() {
        super.init()
#if os(iOS)
        let manager = CLLocationManager()
        locationManager = manager
        manager.delegate = self
        updateAuthorizationStatus(manager.authorizationStatus)
        manager.requestWhenInUseAuthorization()
#endif
        refresh()
    }

    func refresh() {
        interface = NetworkInterfaceResolver.primaryIPv4Interface()
        updateWiFiDisplay()
    }

    var networkDescription: String {
        guard let detail = interface else { return "No active network" }
        return detail.networkAddressOnly
    }

    var ipDescription: String {
        guard let detail = interface else { return "Not available" }
        return detail.ipAddress
    }

    private func updateWiFiDisplay() {
        guard interface != nil else {
            wifiDisplay = "Not available"
            return
        }
#if os(iOS)
        guard isLocationPermissionGranted else {
            wifiDisplay = "Requires Location Permission"
            return
        }
        wifiDisplay = "Loading..."
        fetchSSIDForIOS { [weak self] ssid in
            guard let self else { return }
            Task { @MainActor in
                if let ssid = ssid, !ssid.isEmpty {
                    self.wifiDisplay = ssid
                } else {
                    // Enhanced error handling similar to NetworkIdentifier
                    let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
                    if isSimulator {
                        self.wifiDisplay = "Simulator (limited Wi-Fi access)"
                    } else {
                        self.wifiDisplay = "Wi-Fi not detected"
                    }
                }
            }
        }
#elseif os(macOS)
        wifiDisplay = macSSIDDisplayValue()
#else
        wifiDisplay = "Not available"
#endif
    }
}

#if os(iOS)
@MainActor
private extension NetworkInfoService {
    func fetchSSIDForIOS(completion: @escaping (String?) -> Void) {
        // Try CNCopyCurrentNetworkInfo first (legacy method)
        if let supportedInterfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in supportedInterfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
                    let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
                    !ssid.isEmpty {
                    completion(ssid)
                    return
                }
            }
        }

        // Try NEHotspotNetwork (iOS 14+)
        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { network in
                let fetchedSSID = (network?.ssid.isEmpty == false) ? network?.ssid : nil
                if let ssid = fetchedSSID {
                    completion(ssid)
                } else {
                    // Enhanced error handling - check if we're on simulator
                    let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
                    if isSimulator {
                        completion("Simulator (limited Wi-Fi access)")
                    } else {
                        completion(nil)
                    }
                }
            }
        } else {
            completion(nil)
        }
    }

    func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        let wasGranted = isLocationPermissionGranted
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocationPermissionGranted = true
            if !wasGranted {
                refresh()
            } else {
                updateWiFiDisplay()
            }
        case .denied:
            isLocationPermissionGranted = false
            wifiDisplay = "Location Permission Denied"
        case .restricted:
            isLocationPermissionGranted = false
            wifiDisplay = "Location Access Restricted"
        case .notDetermined:
            isLocationPermissionGranted = false
            wifiDisplay = "Requires Location Permission"
        @unknown default:
            isLocationPermissionGranted = false
            wifiDisplay = "Not available"
        }
    }
}

@MainActor
extension NetworkInfoService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        updateAuthorizationStatus(status)
    }
}
#endif

#if os(macOS)
private extension NetworkInfoService {
    func macSSIDDisplayValue() -> String {
        let client = CWWiFiClient.shared()
        if let primaryInterface = client.interface(), let ssid = primaryInterface.ssid(), !ssid.isEmpty {
            return ssid
        }

        if let interfaces = client.interfaces() {
            for interface in interfaces {
                if let ssid = interface.ssid(), !ssid.isEmpty {
                    return ssid
                }
            }
        }

        let locationStatus: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
            locationStatus = CLLocationManager().authorizationStatus
        } else {
            locationStatus = CLLocationManager.authorizationStatus()
        }

        switch locationStatus {
        case .denied, .restricted:
            return "Location Services Denied"
        case .notDetermined:
            return "Location Services Required"
        default:
            break
        }

        if !CLLocationManager.locationServicesEnabled() {
            return "Location Services Disabled"
        }

        // Check if Wi-Fi is actually connected
        if let primaryInterface = client.interface() {
            if primaryInterface.ssid() == nil {
                return "No Wi-Fi Connection"
            }
        }

        return "Wi-Fi not detected"
    }
}
#endif
