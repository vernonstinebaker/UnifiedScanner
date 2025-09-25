import Foundation
import Combine

@MainActor
protocol DevicePersistenceCoordinating {
    func initialLoad() -> [Device]
    func save(devices: [Device])
    func clearAllData()
    func reloadIfChanged(currentIDs: [String]) -> [Device]?
}

@MainActor
final class DevicePersistenceCoordinator: DevicePersistenceCoordinating {
    private let persistence: DevicePersistence
    private let persistenceKey: String

    init(persistence: DevicePersistence, key: String) {
        self.persistence = persistence
        self.persistenceKey = key
    }

    func initialLoad() -> [Device] {
        persistence.load(key: persistenceKey)
    }

    func save(devices: [Device]) {
        persistence.save(devices, key: persistenceKey)
    }

    func clearAllData() {
        persistence.save([], key: persistenceKey)
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        let ubi = NSUbiquitousKeyValueStore.default
        ubi.removeObject(forKey: persistenceKey)
        ubi.synchronize()
    }

    func reloadIfChanged(currentIDs: [String]) -> [Device]? {
        let latest = persistence.load(key: persistenceKey)
        let latestIDs = latest.map(\.id)
        guard latestIDs != currentIDs || latestIDs.count != currentIDs.count else {
            return nil
        }
        return latest
    }
}

@MainActor
protocol DeviceClassificationCoordinating {
    func classify(_ device: Device) async -> Device.Classification
    func shouldReclassify(old: Device, merged: Device) -> Bool
}

@MainActor
final class DeviceClassificationCoordinator: DeviceClassificationCoordinating {
    private let classificationService: ClassificationService.Type

    init(service: ClassificationService.Type = ClassificationService.self) {
        self.classificationService = service
    }

    func classify(_ device: Device) async -> Device.Classification {
        await classificationService.classify(device: device)
    }

    func shouldReclassify(old: Device, merged: Device) -> Bool {
        fingerprint(of: old) != fingerprint(of: merged)
    }

    private func fingerprint(of device: Device) -> String {
        let serviceKey = device.services
            .map { $0.type.rawValue + "|\($0.port ?? -1)" }
            .sorted()
            .joined(separator: ",")
        let portKey = device.openPorts
            .map { "\($0.number)/\($0.transport)" }
            .sorted()
            .joined(separator: ",")
        let fingerprintKey = (device.fingerprints ?? [:])
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
        return "host=\(device.hostname ?? "")|vendor=\(device.vendor ?? "")|model=\(device.modelHint ?? "")|svc=\(serviceKey)|ports=\(portKey)|fp=\(fingerprintKey)"
    }
}

@MainActor
protocol DeviceMutationPublishing {
    func emit(_ mutation: DeviceMutation)
    func mutationStream(includeBuffered: Bool) -> AsyncStream<DeviceMutation>
    func clearBuffer()
}

@MainActor
struct DeviceMutationBusPublisher: DeviceMutationPublishing {
    private let bus: DeviceMutationBus

    init(bus: DeviceMutationBus = .shared) {
        self.bus = bus
    }

    func emit(_ mutation: DeviceMutation) {
        bus.emit(mutation)
    }

    func mutationStream(includeBuffered: Bool) -> AsyncStream<DeviceMutation> {
        bus.mutationStream(includeBuffered: includeBuffered)
    }

    func clearBuffer() {
        bus.clearBuffer()
    }
}

protocol SnapshotClock {
    var now: Date { get }
    func sleep(seconds: TimeInterval) async
}

struct SystemSnapshotClock: SnapshotClock {
    var now: Date { Date() }

    func sleep(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64((seconds * 1_000_000_000).rounded())
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

// MARK: - Mutation Stream Types
public enum DeviceField: String, CaseIterable, Sendable {
    case hostname, vendor, modelHint, rttMillis, services, openPorts, discoverySources, classification, ips, primaryIP, lastSeen, firstSeen, macAddress, fingerprints, isOnlineOverride
}

public enum MutationSource: Sendable { case mdns, ping, arp, portScan, httpFingerprint, classification, persistenceRestore, offline }

public struct DeviceChange: Sendable {
    public let before: Device?
    public let after: Device
    public let changed: Set<DeviceField>
    public let source: MutationSource
    public init(before: Device?, after: Device, changed: Set<DeviceField>, source: MutationSource) {
        self.before = before
        self.after = after
        self.changed = changed
        self.source = source
    }
}

public enum DeviceMutation: Sendable {
    case snapshot([Device])
    case change(DeviceChange)
    case ping(PingMeasurement)
}

extension DeviceField {
    static func differences(old: Device, new: Device) -> Set<DeviceField> {
        var result: Set<DeviceField> = []
        if old.hostname != new.hostname { result.insert(.hostname) }
        if old.vendor != new.vendor { result.insert(.vendor) }
        if old.modelHint != new.modelHint { result.insert(.modelHint) }
        if old.rttMillis != new.rttMillis { result.insert(.rttMillis) }
        if old.services != new.services { result.insert(.services) }
        if old.openPorts != new.openPorts { result.insert(.openPorts) }
        if old.discoverySources != new.discoverySources { result.insert(.discoverySources) }
        if old.classification != new.classification { result.insert(.classification) }
        if old.ips != new.ips { result.insert(.ips) }
        if old.primaryIP != new.primaryIP { result.insert(.primaryIP) }
        if old.lastSeen != new.lastSeen { result.insert(.lastSeen) }
        if old.firstSeen != new.firstSeen { result.insert(.firstSeen) }
        if old.macAddress != new.macAddress { result.insert(.macAddress) }
        if old.fingerprints != new.fingerprints { result.insert(.fingerprints) }
        if old.isOnlineOverride != new.isOnlineOverride { result.insert(.isOnlineOverride) }
        return result
    }
}

/// Actor-backed store responsible for maintaining the current set of Devices.
/// Performs merge (upsert) operations and persists snapshots to iCloud Key-Value store.
/// Persistence Strategy:
///  - Serialize full device array to JSON under a versioned key in NSUbiquitousKeyValueStore
///  - Also mirrors to UserDefaults for fast local restore
///  - Listens for external KVS change notifications (not implemented yet; hook in UI layer)
/// Merge Semantics:
///  - Identity: existing device matched by `id` (stable: MAC > primaryIP > hostname > generated UUID)
///  - Preserve `firstSeen` (set if absent)
///  - Update `lastSeen` to `Date()` on any merge
///  - Union IPs, discoverySources
///  - Update primaryIP if new candidate arrives and existing is nil
///  - Merge services & openPorts with deduplication (ServiceDeriver then port uniqueness)
///  - Classification is re-run automatically when any of: hostname, vendor, services, openPorts change
///  - RTT and latency fields overwritten if new value provided (latest wins)
@MainActor
final class SnapshotService: ObservableObject {
     @Published private(set) var devices: [Device] = []
     private var mutationContinuations: [UUID: AsyncStream<DeviceMutation>.Continuation] = [:]

     private var offlineHeartbeatTask: Task<Void, Never>? = nil
     private let offlineCheckInterval: TimeInterval
     private let onlineGraceInterval: TimeInterval

     private let persistenceCoordinator: DevicePersistenceCoordinating
     private let classificationCoordinator: DeviceClassificationCoordinating
     private let mutationPublisher: DeviceMutationPublishing
     private let clock: SnapshotClock
     private let localIPv4Networks: [IPv4Network]
     private var mutationListenerTask: Task<Void, Never>? = nil

     init(persistenceKey: String = "unifiedscanner:devices:v1",
          persistence: DevicePersistence? = nil,
          classification: ClassificationService.Type = ClassificationService.self,
          offlineCheckInterval: TimeInterval = 60,
          onlineGraceInterval: TimeInterval = DeviceConstants.onlineGraceInterval,
          mutationPublisher: DeviceMutationPublishing? = nil,
          persistenceCoordinator: DevicePersistenceCoordinating? = nil,
          classificationCoordinator: DeviceClassificationCoordinating? = nil,
          clock: SnapshotClock = SystemSnapshotClock()) {
         let resolvedPersistence = persistence ?? LiveDevicePersistence()
         self.persistenceCoordinator = persistenceCoordinator ?? DevicePersistenceCoordinator(persistence: resolvedPersistence, key: persistenceKey)
         self.classificationCoordinator = classificationCoordinator ?? DeviceClassificationCoordinator(service: classification)
         self.mutationPublisher = mutationPublisher ?? DeviceMutationBusPublisher()
         self.clock = clock
         self.offlineCheckInterval = offlineCheckInterval
         self.onlineGraceInterval = onlineGraceInterval
         self.localIPv4Networks = LocalSubnetEnumerator.activeIPv4Networks()
        let env = ProcessInfo.processInfo.environment
        let disablePersistence = env["UNIFIEDSCANNER_DISABLE_PERSISTENCE"] == "1"
        if disablePersistence {
            self.devices = []
        } else {
            self.devices = self.persistenceCoordinator.initialLoad()
             if true { // forceOfflineOnRestore now always-on
                self.devices = self.devices.map { dev in
                    var d = dev
                    d.isOnlineOverride = false
                    return d
                }
            }
             self.devices = self.devices.compactMap { sanitize(device: $0) }
             // Re-resolve autoName with latest logic (non-destructive to user overrides)
             for i in devices.indices {
                 if devices[i].name == nil { // only adjust autoName if not user-specified
                     if let resolved = DeviceDisplayNameResolver.resolve(for: devices[i]) {
                         devices[i].autoName = resolved.value
                     }
                 }
             }
             // Sort loaded devices
             self.devices.sort { (lhs, rhs) -> Bool in
                 let lhsIP = lhs.bestDisplayIP ?? lhs.primaryIP ?? "255.255.255.255"
                 let rhsIP = rhs.bestDisplayIP ?? rhs.primaryIP ?? "255.255.255.255"
                 return compareIPs(lhsIP, rhsIP)
              }
         }
        if env["UNIFIEDSCANNER_CLEAR_ON_START"] == "1" {
            self.devices.removeAll()
            persist()
        }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.reloadFromPersistenceIfChanged()
            }
         }
         startOfflineHeartbeat()
         startMutationListener()
     }

    private func startMutationListener() {
        mutationListenerTask?.cancel()
        mutationListenerTask = Task { [weak self] in
            guard let self else { return }
            let stream = mutationPublisher.mutationStream(includeBuffered: true)
            for await mutation in stream {
                if Task.isCancelled { break }
                await self.applyMutation(mutation)
            }
        }
    }

     @MainActor
     private func applyMutation(_ mutation: DeviceMutation) async {
         switch mutation {
         case .snapshot(let devices):
             // Replace all devices with snapshot
             self.devices = devices
             sortDevices()
             persist()
             emit(.snapshot(devices))
         case .change(let change):
             // Apply the change using existing upsert logic
             await self.upsert(change.after, source: change.source)
         case .ping(let measurement):
             // Delegate to ping logic (creates device only on success)
             await self.applyPing(measurement)
         }
     }
     
     private func startOfflineHeartbeat() {
         // Skip offline heartbeat in test environment to prevent tests from hanging
          offlineHeartbeatTask?.cancel()
        offlineHeartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.performOfflineSweep()
                await self.clock.sleep(seconds: self.offlineCheckInterval)
            }
        }
     }
     
     private func performOfflineSweep() async {
        let now = clock.now
         var mutations: [DeviceChange] = []
         for (idx, dev) in devices.enumerated() {
             guard dev.isOnlineOverride != false else { continue }
             guard let last = dev.lastSeen else { continue }
              if now.timeIntervalSince(last) > self.onlineGraceInterval {
                 var updated = dev
                 updated.isOnlineOverride = false
                 devices[idx] = updated
                 let changed: Set<DeviceField> = [.isOnlineOverride]
                 mutations.append(DeviceChange(before: dev, after: updated, changed: changed, source: .offline))
             }
         }
         if !mutations.isEmpty { for m in mutations { emit(.change(m)) } }
     }
     
     // MARK: - Public API
    func mutationStream(includeInitialSnapshot: Bool = true, buffer: Int = 256) -> AsyncStream<DeviceMutation> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingOldest(buffer)) { continuation in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationContinuations[id] = continuation
                if includeInitialSnapshot { continuation.yield(.snapshot(self.devices)) }
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.mutationContinuations.removeValue(forKey: id)
                    }
                }
            }
        }
    }

    private func emit(_ mutation: DeviceMutation) {
        for (_, cont) in mutationContinuations { cont.yield(mutation) }
    }

    func upsert(_ incoming: Device, source: MutationSource = .mdns) async {
        guard var incoming = sanitize(device: incoming) else {
            let ipSummary = incoming.ips.sorted().joined(separator: ",")
            LoggingService.debug("snapshot: skip filtered device primary=\(incoming.primaryIP ?? "nil") ips=\(ipSummary)", category: .snapshot)
            return
        }

        if source == .mdns {
            let primary = incoming.primaryIP ?? "nil"
            let ipsCount = incoming.ips.count
            let hostname = incoming.hostname ?? "nil"
            let servicesSummary = incoming.services.map { "\($0.type.rawValue):\($0.port ?? -1)" }.joined(separator: ",")
            let message = "snapshot: upsert mdns incoming primary=\(primary) ips=\(ipsCount) hostname=\(hostname) services=\(servicesSummary)"
            LoggingService.info(message, category: .snapshot)
        }
        // Clear offline override if we have fresh activity
        if incoming.isOnlineOverride == false { incoming.isOnlineOverride = nil }
        let matchIndex = indexForDevice(incoming)
        let before = matchIndex.map { devices[$0] }
        var newDevice = incoming
        if newDevice.firstSeen == nil { newDevice.firstSeen = Date() }
        newDevice.lastSeen = Date()

        var changedFields: Set<DeviceField> = []
        if let idx = matchIndex {
            let merged = await merge(existing: devices[idx], incoming: newDevice)
            if let cleaned = sanitize(device: merged) {
                let old = devices[idx]
                devices[idx] = cleaned
                changedFields.formUnion(DeviceField.differences(old: old, new: cleaned))
            } else {
                devices.remove(at: idx)
                sortDevices()
                persist()
                emit(.snapshot(devices))
                return
            }
        } else {
            if var sanitized = sanitize(device: newDevice) {
                sanitized.classification = await classificationCoordinator.classify(sanitized)
                newDevice = sanitized
                devices.append(sanitized)
                changedFields = Set(DeviceField.allCases)
            } else {
                return
            }
        }
         // Sort devices after modification
         sortDevices()
        persist()
        // Derive autoName if needed (after merge and potential classification)
        if let idx = devices.firstIndex(where: { $0.id == (before?.id ?? newDevice.id) }) {
            var dev = devices[idx]
            let previousAuto = dev.autoName
            if dev.name == nil { // only set if no user override
                if let resolved = DeviceDisplayNameResolver.resolve(for: dev) {
                    if previousAuto != resolved.value {
                        let logMsg = "name_resolver: set autoName=\(resolved.value) score=\(resolved.score) id=\(dev.id)"
                        LoggingService.debug(logMsg, category: .snapshot)
                        dev.autoName = resolved.value
                        devices[idx] = dev
                        changedFields.insert(.hostname) // piggyback to trigger UI refresh
                    }
                }
            }
        }
        if !changedFields.isEmpty {
            let after = devices.first(where: { $0.id == (before?.id ?? newDevice.id) }) ?? newDevice
            emit(.change(DeviceChange(before: before, after: after, changed: changedFields, source: source)))
        }
    }

    func upsertMany(_ list: [Device], source: MutationSource = .mdns) async {
        for d in list { await upsert(d, source: source) }
    }

      func applyPing(_ measurement: PingMeasurement) async {
            LoggingService.debug("applyPing host=\(measurement.host) status=\(measurement.status)", category: .snapshot)
            // Find existing device by primary or secondary IP
           if let idx = devices.firstIndex(where: { $0.primaryIP == measurement.host || $0.ips.contains(measurement.host) }) {
              var dev = devices[idx]
              switch measurement.status {
              case .success(let rtt):
                  dev.rttMillis = rtt
                  dev.lastSeen = measurement.timestamp
                  dev.discoverySources.insert(.ping)
                  dev.isOnlineOverride = nil
              case .timeout, .unreachable, .error:
                  LoggingService.debug("ignore non-success existing host=\(measurement.host) status=\(measurement.status)", category: .snapshot)
                  break
              }
                let old = devices[idx]
                devices[idx] = dev
                // Sort after modification
                sortDevices()
               persist()
               let changed = DeviceField.differences(old: old, new: dev)
               if !changed.isEmpty { emit(.change(DeviceChange(before: old, after: dev, changed: changed, source: .ping))) }
           } else {
               // Only create a new device on successful ping to avoid cluttering UI with non-responsive hosts.
               guard case .success(let rtt) = measurement.status else {
                    LoggingService.debug("suppress creation host=\(measurement.host) status=\(measurement.status)", category: .snapshot)
                   return
               }
               // Skip creating device for invalid IPs
               guard shouldKeepIP(measurement.host) else {
                   LoggingService.debug("suppress creation for invalid IP host=\(measurement.host)", category: .snapshot)
                   return
               }
               var newDevice = Device(primaryIP: measurement.host, ips: [measurement.host], discoverySources: [.ping])
               newDevice.rttMillis = rtt
               newDevice.firstSeen = measurement.timestamp
               newDevice.lastSeen = measurement.timestamp
              if var sanitized = sanitize(device: newDevice) {
                  sanitized.classification = await classificationCoordinator.classify(sanitized)
                  newDevice = sanitized
                  devices.append(sanitized)
                  // Sort after modification
                  sortDevices()
                  persist()
                  emit(.change(DeviceChange(before: nil, after: sanitized, changed: Set(DeviceField.allCases), source: .ping)))
              }
           }
       }

    func refreshClassifications() async {
        var mutations: [DeviceChange] = []
        var newDevices: [Device] = []
        for dev in devices {
            var copy = dev
            let newClass = await classificationCoordinator.classify(dev)
            if dev.classification != newClass {
                let before = dev
                copy.classification = newClass
                let changed: Set<DeviceField> = [.classification]
                mutations.append(DeviceChange(before: before, after: copy, changed: changed, source: .classification))
            }
            newDevices.append(copy)
        }
        devices = newDevices
               // Sort after modification
               sortDevices()
        persist()
        for m in mutations { emit(.change(m)) }
    }

    private func sortDevices() {
        devices.sort { (lhs, rhs) -> Bool in
            let lhsIP = lhs.bestDisplayIP ?? lhs.primaryIP ?? "255.255.255.255"
            let rhsIP = rhs.bestDisplayIP ?? rhs.primaryIP ?? "255.255.255.255"
            return compareIPs(lhsIP, rhsIP)
        }
    }

    func removeAll() {
        devices.removeAll()
        persist()
        emit(.snapshot(devices))
    }

    func clearAllData() {
        devices.removeAll()
        persistenceCoordinator.clearAllData()
        emit(.snapshot(devices))
    }

    // MARK: - Merge Logic
    private func merge(existing: Device, incoming: Device) async -> Device {
        var result = existing

        // Identity-level fields
        if result.primaryIP == nil, let p = incoming.primaryIP { result.primaryIP = p }

        // Sets / unions
        result.ips.formUnion(incoming.ips)
        result.discoverySources.formUnion(incoming.discoverySources)

        // Simple overwrites if new non-nil provided
        if let host = incoming.hostname, !host.isEmpty { result.hostname = host }
        if let mac = incoming.macAddress, !mac.isEmpty { result.macAddress = mac }
        if let vendor = incoming.vendor, !vendor.isEmpty { result.vendor = vendor }
        if let model = incoming.modelHint, !model.isEmpty { result.modelHint = model }
        if let rtt = incoming.rttMillis { result.rttMillis = rtt }

        // Services merge (dedupe by (rawType/type, port))
        if !incoming.services.isEmpty || !incoming.openPorts.isEmpty {
            let combinedServices = result.services + incoming.services
            // Dedup services by (type, port, name) preference: keep earlier (existing) unless incoming has more descriptive name
            var serviceMap: [String: NetworkService] = [:]
            for svc in combinedServices {
                let key = "\(svc.type.rawValue)|\(svc.port ?? -1)"
                if let existing = serviceMap[key] {
                    // Prefer name with greater length (heuristic for descriptiveness)
                    if svc.name.count > existing.name.count { serviceMap[key] = svc }
                } else { serviceMap[key] = svc }
            }
            let deduped = Array(serviceMap.values)
            // Use ServiceDeriver for display ordering
            result.services = deduped.sorted { a, b in
                if a.type == b.type { return (a.port ?? 0) < (b.port ?? 0) }
                return a.type.rawValue < b.type.rawValue
            }

            // Ports merge (dedupe by number+transport+status preference open>filtered>closed)
            var portMap: [String: Port] = [:]
            for p in result.openPorts + incoming.openPorts {
                let key = "\(p.number)/\(p.transport)"
                if let ex = portMap[key] {
                    // Prefer open > filtered > closed, else keep earliest
                    let priority: (Port.Status) -> Int = { st in
                        switch st { case .open: return 0; case .filtered: return 1; case .closed: return 2 }
                    }
                    if priority(p.status) < priority(ex.status) { portMap[key] = p }
                } else { portMap[key] = p }
            }
            result.openPorts = Array(portMap.values).sorted { $0.number < $1.number }
        }

        // Fingerprints merge (shallow union)
        if let incFP = incoming.fingerprints {
            var fp = result.fingerprints ?? [:]
            for (k,v) in incFP where !v.isEmpty { fp[k] = v }
            result.fingerprints = fp
            let extracted = VendorModelExtractorService.extract(from: fp)
            if (result.vendor == nil || result.vendor?.isEmpty == true), let derivedVendor = extracted.vendor, !derivedVendor.isEmpty {
                result.vendor = derivedVendor
            }
            if (result.modelHint == nil || result.modelHint?.isEmpty == true), let derivedModel = extracted.model, !derivedModel.isEmpty {
                result.modelHint = derivedModel
            }
        }

        // Timestamps
        result.lastSeen = incoming.lastSeen ?? Date()
        if result.firstSeen == nil { result.firstSeen = incoming.firstSeen ?? Date() }

        // Online override adopts latest signal (nil clears forced-offline state)
        result.isOnlineOverride = incoming.isOnlineOverride

        // Recompute classification if relevant fields changed
        if classificationCoordinator.shouldReclassify(old: existing, merged: result) {
            result.classification = await classificationCoordinator.classify(result)
        }

        return result
    }

    // MARK: - Persistence
    private func persist() {
        persistenceCoordinator.save(devices: devices)
    }

    func saveSnapshotNow() {
        persist()
    }

    private func compareIPs(_ ip1: String, _ ip2: String) -> Bool {
        // Handle IPv4 addresses with proper numerical comparison
        let ip1Parts = ip1.split(separator: ".").compactMap { Int($0) }
        let ip2Parts = ip2.split(separator: ".").compactMap { Int($0) }

        if ip1Parts.count == 4 && ip2Parts.count == 4 {
            for (p1, p2) in zip(ip1Parts, ip2Parts) {
                if p1 != p2 {
                    return p1 < p2
                }
            }
            return false // IPs are equal
        }

        // Fallback to string comparison for non-IPv4 or malformed IPs
        return ip1 < ip2
    }

    private func reloadFromPersistenceIfChanged() async {
        guard let latest = persistenceCoordinator.reloadIfChanged(currentIDs: devices.map(\.id)) else {
            return
        }
        // Only replace if different count or ids changed
        // Re-run classification to ensure consistency if loaded persisted snapshot lacks it (older version)
        var newDevices: [Device] = []
        for dev in latest {
            var d = dev
            if d.classification == nil { d.classification = await classificationCoordinator.classify(d) }
            newDevices.append(d)
        }
        devices = newDevices
        // Sort after loading
        sortDevices()
        emit(.snapshot(devices))
    }
}

private extension SnapshotService {
    func isLocalIPv4(_ ip: String) -> Bool {
        guard !ip.hasPrefix("169.254.") else { return false }
        if ip.hasSuffix(".255") { return false }
        // Allow common test/private IP ranges
        if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") { return true }
        guard let value = IPv4Parser.addressToUInt32(ip) else { return false }
        if localIPv4Networks.isEmpty { return true }
        return localIPv4Networks.contains { network in
            (value & network.netmask) == network.networkAddress
        }
    }

    func shouldKeepIP(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("127.") { return false }
        if trimmed == "::1" { return false }
        if trimmed.contains(":") { return true }
        // Exclude IPv4 broadcast addresses (simple heuristic: ends with .255)
        if trimmed.hasSuffix(".255") { return false }
        // Exclude IPv4 broadcast addresses for detected local networks
        if let value = IPv4Parser.addressToUInt32(trimmed) {
            for net in localIPv4Networks {
                let broadcast = (net.networkAddress & net.netmask) | (~net.netmask)
                if value == broadcast { return false }
            }
        }
        return isLocalIPv4(trimmed)
    }

    func sanitize(device: Device) -> Device? {
        var filteredIPs: Set<String> = []
        for ip in device.ips where shouldKeepIP(ip) {
            filteredIPs.insert(ip.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var sanitized = device

        if let primary = device.primaryIP, shouldKeepIP(primary) {
            sanitized.primaryIP = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            sanitized.primaryIP = filteredIPs.sorted().first
        }

        sanitized.ips = filteredIPs

        if (sanitized.vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fingerprints = sanitized.fingerprints {
                let extracted = VendorModelExtractorService.extract(from: fingerprints)
                if let vendor = extracted.vendor, !vendor.isEmpty {
                    sanitized.vendor = vendor
                }
                if (sanitized.modelHint ?? "").isEmpty, let model = extracted.model, !model.isEmpty {
                    sanitized.modelHint = model
                }
            }
            if (sanitized.vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let mac = sanitized.macAddress,
               let vendor = OUILookupService.shared.vendorFor(mac: mac) {
                sanitized.vendor = vendor
            }
        }

        if sanitized.primaryIP == nil && sanitized.ips.isEmpty {
            LoggingService.debug("snapshot: sanitize drop device id=\(device.id) no valid IPs left", category: .snapshot)
            return nil
        }

        return sanitized
    }

    func indexForDevice(_ incoming: Device) -> Int? {
        // 1. Exact ID match (fast path)
        if let idx = devices.firstIndex(where: { $0.id == incoming.id }) { return idx }

        // 2. MAC address match (normalized)
        if let mac = incoming.macAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !mac.isEmpty {
            let normalized = Device.normalizeMAC(mac)
            if let idx = devices.firstIndex(where: { device in
                guard let existingMAC = device.macAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !existingMAC.isEmpty else { return false }
                return Device.normalizeMAC(existingMAC) == normalized
            }) { return idx }
        }

        // 3. Primary IP match
        if let primary = incoming.primaryIP?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            if let idx = devices.firstIndex(where: { $0.primaryIP == primary }) { return idx }
        }

        // 4. Any IP overlap
        if !incoming.ips.isEmpty {
            let ips = incoming.ips
            if let idx = devices.firstIndex(where: { !$0.ips.isDisjoint(with: ips) }) { return idx }
        }

        // 5. Hostname match as a last resort
        if let host = incoming.hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            if let idx = devices.firstIndex(where: { $0.hostname == host }) { return idx }
        }

        return nil
    }
}

// Backwards compatibility during migration

// MARK: - Persistence Adapter
protocol DevicePersistence {
    func load(key: String) -> [Device]
    func save(_ devices: [Device], key: String)
}

extension DevicePersistence {
    static var live: DevicePersistence { LiveDevicePersistence() }
}

struct LiveDevicePersistence: DevicePersistence {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Explicitly nonisolated to avoid implicit @MainActor inference
    nonisolated func load(key: String) -> [Device] {
        let ubi = NSUbiquitousKeyValueStore.default
        if let data = ubi.data(forKey: key) ?? (ubi.object(forKey: key) as? Data) {
            if let arr = try? decoder.decode([Device].self, from: data) { return arr }
        }
        if let data = UserDefaults.standard.data(forKey: key), let arr = try? decoder.decode([Device].self, from: data) { return arr }
        return []
    }

    nonisolated func save(_ devices: [Device], key: String) {
        guard let data = try? encoder.encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: key)
        let ubi = NSUbiquitousKeyValueStore.default
        ubi.set(data, forKey: key)
        ubi.synchronize()
    }
}
