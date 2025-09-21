import Foundation
import Network

protocol PortProbing: Sendable {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortProbeResult
}

enum PortProbeResult: Sendable {
    case open
    case closed
    case timeout
}

final class NWPortProber: PortProbing {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortProbeResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .closed }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "PortProber.\(host).\(port)")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let state = AtomicFlag()

            let finish: @Sendable (PortProbeResult) -> Void = { result in
                guard state.trySet() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.open)
                case .failed:
                    finish(.closed)
                case .cancelled:
                    finish(.closed)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.timeout)
            }
        }
    }
}

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false

    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if set { return false }
        set = true
        return true
    }
}

actor PortScanService {
    private struct HostScanKey: Hashable { let id: String; let host: String }

    private let mutationBus: DeviceMutationBus
    private let ports: [UInt16]
    private let timeout: TimeInterval
    private let rescanInterval: TimeInterval
    private let prober: PortProbing

    private var inFlight: Set<HostScanKey> = []
    private var lastScan: [HostScanKey: Date] = [:]
    private var listenTask: Task<Void, Never>? = nil

    init(mutationBus: DeviceMutationBus,
         ports: [UInt16] = [22, 80, 443],
         timeout: TimeInterval = 1.5,
         rescanInterval: TimeInterval = 300,
         prober: PortProbing? = nil) {
        self.mutationBus = mutationBus
        self.ports = ports
        self.timeout = timeout
        self.rescanInterval = rescanInterval
        self.prober = prober ?? NWPortProber()
    }

    func start() {
        guard listenTask == nil else { return }
        listenTask = Task { await listenForDevices() }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
    }

    private func listenForDevices() async {
        let stream = await MainActor.run { mutationBus.mutationStream(includeBuffered: false) }
        for await mutation in stream {
            if Task.isCancelled { break }
            guard case .change(let change) = mutation else { continue }
            guard shouldScan(change: change) else { continue }
            let hosts = hostsToScan(from: change.after)
            for host in hosts {
                await enqueueScan(for: host, device: change.after)
            }
        }
    }

    private func shouldScan(change: DeviceChange) -> Bool {
        if change.source == .portScan { return false }
        guard !ports.isEmpty else { return false }
        if change.before == nil { return true }
        if change.changed.contains(.primaryIP) || change.changed.contains(.ips) { return true }
        return false
    }

    private func hostsToScan(from device: Device) -> [String] {
        var candidates: [String] = []
        if let primary = device.primaryIP, isScannable(host: primary) {
            candidates.append(primary)
        }
        for ip in device.ips where isScannable(host: ip) {
            if !candidates.contains(ip) { candidates.append(ip) }
        }
        return candidates
    }

    private func isScannable(host: String) -> Bool {
        guard !host.isEmpty else { return false }
        if host.contains(":") { return false } // Skip IPv6 for now
        if host.hasPrefix("127.") { return false }
        if host.hasPrefix("169.254.") { return false }
        return true
    }

    private func enqueueScan(for host: String, device: Device) async {
        let key = HostScanKey(id: device.id, host: host)
        if inFlight.contains(key) { return }
        let now = Date()
        if let last = lastScan[key], now.timeIntervalSince(last) < rescanInterval { return }
        inFlight.insert(key)
        lastScan[key] = now
        Task { [weak self] in
            await self?.performScan(for: key, device: device)
        }
    }

    private func performScan(for key: HostScanKey, device: Device) async {
        let host = key.host
        var openPorts: [UInt16] = []
        for port in ports {
            let result = await prober.probe(host: host, port: port, timeout: timeout)
            if case .open = result {
                openPorts.append(port)
            }
        }
        if !openPorts.isEmpty {
            await emitMutation(for: device, host: host, openPorts: openPorts)
        }
        cleanup(key: key)
    }

    private func cleanup(key: HostScanKey) {
        inFlight.remove(key)
    }

    private func emitMutation(for device: Device, host: String, openPorts: [UInt16]) async {
        let now = Date()
        let portModels: [Port] = openPorts.map { number in
            let mapping = ServiceDeriver.wellKnownPorts[Int(number)]
            return Port(number: Int(number),
                        transport: "tcp",
                        serviceName: mapping?.1 ?? "Port \(number)",
                        description: mapping?.1 ?? "Open TCP port \(number)",
                        status: .open,
                        lastSeenOpen: now)
        }
        var services: [NetworkService] = []
        for port in openPorts {
            if let mapping = ServiceDeriver.wellKnownPorts[Int(port)] {
                let svc = NetworkService(name: mapping.1,
                                         type: mapping.0,
                                         rawType: nil,
                                         port: Int(port),
                                         isStandardPort: true)
                services.append(svc)
            }
        }
        let discoverySources: Set<DiscoverySource> = [.portScan]
        var ips = device.ips
        ips.insert(host)
        let update = Device(id: device.id,
                            primaryIP: device.primaryIP ?? host,
                            ips: ips.isEmpty ? [host] : ips,
                            hostname: device.hostname,
                            macAddress: device.macAddress,
                            vendor: device.vendor,
                            modelHint: device.modelHint,
                            classification: device.classification,
                            discoverySources: discoverySources,
                            rttMillis: nil,
                            services: services,
                            openPorts: portModels,
                            fingerprints: nil,
                            firstSeen: device.firstSeen,
                            lastSeen: now,
                            isOnlineOverride: device.isOnline ? device.isOnlineOverride : true)
        let changed: Set<DeviceField> = [.openPorts, .services, .discoverySources, .lastSeen, .isOnlineOverride]
        let change = DeviceChange(before: nil, after: update, changed: changed, source: .portScan)
        await MainActor.run {
            mutationBus.emit(.change(change))
        }
    }
}
