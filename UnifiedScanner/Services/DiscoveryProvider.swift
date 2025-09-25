import Foundation
import Combine
#if canImport(Darwin)
import Darwin
#endif

// MARK: - ScanProgress
@MainActor
final class ScanProgress: ObservableObject {
    enum Phase: String, CaseIterable { case idle, mdnsWarmup, enumerating, arpPriming, pinging, arpRefresh, complete }

    @Published var phase: Phase = .idle
    @Published var totalHosts: Int = 0
    @Published var completedHosts: Int = 0
    @Published var started: Bool = false
    @Published var finished: Bool = false {
        didSet {
            if finished && phase != .complete { phase = .complete }
        }
    }
    @Published var successHosts: Int = 0

    private func log(_ message: String) { LoggingService.debug(message, category: .discovery) }

    func reset() async {
        await setPhase(.idle)
        log("reset (prev total=\(totalHosts) completed=\(completedHosts) success=\(successHosts))")
        totalHosts = 0
        completedHosts = 0
        successHosts = 0
        started = false
        finished = false
    }

    func begin(total: Int) async {
        await setPhase(.pinging)
        log("begin total=\(total)")
        started = true
        finished = false
        completedHosts = 0
        successHosts = 0
        totalHosts = total
    }

    func incrementCompleted() async {
        completedHosts += 1
        if completedHosts >= totalHosts && totalHosts > 0 {
            finished = true
            log("finished (completed=\(completedHosts) total=\(totalHosts))")
        }
    }

    func incrementSuccess() async { successHosts += 1 }

    func getCurrentProgress() async -> (total: Int, completed: Int, success: Int, started: Bool, finished: Bool, phase: Phase) {
        (totalHosts, completedHosts, successHosts, started, finished, phase)
    }

    func setPhase(_ newPhase: Phase) async {
        phase = newPhase
    }
}

// MARK: - DiscoveryProvider Protocol
public protocol DiscoveryProvider: AnyObject, Sendable {
    var name: String { get }
    func start(mutationBus: DeviceMutationBus) -> AsyncStream<DeviceMutation>
    func stop()
}

// MARK: - BonjourDiscoveryProvider
public final class BonjourDiscoveryProvider: NSObject, @unchecked Sendable, DiscoveryProvider {
    public let name = "bonjour-mdns"
    private let resolveCooldown: TimeInterval
    private let dynamicBrowserCap: Int
    private var stopped = false
    private var continuation: AsyncStream<Device>.Continuation?

    // New decomposed services
    private var browseService: BonjourBrowseService?
    private var resolveService: BonjourResolveService?

    // Curated service baseline
    private let curatedServiceTypes: [String] = [
        "_airplay._tcp.", "_raop._tcp.", "_ssh._tcp.", "_http._tcp.", "_https._tcp.",
        "_hap._tcp.", "_spotify-connect._tcp.", "_smb._tcp.", "_ipp._tcp.", "_printer._tcp.",
        "_rfb._tcp.", "_afpovertcp._tcp.", "_sftp-ssh._tcp.",
        "_miio._udp.", "_googlecast._tcp.", "_amazonecho._tcp.", "_presence-tls._tcp.",
        "_mediaremotetv._tcp.", "_asquic._udp.", "_companion-link._tcp.",
        "_touch-able._tcp.", "_sleep-proxy._udp.", "_device-info._tcp."
    ]

#if os(iOS)
    private let additionalIOSAllowedTypes: [String] = [
        "_apple-mobdev2._tcp.", "_remotepairing._tcp."
    ]
#else
    private let additionalIOSAllowedTypes: [String] = []
#endif

    // Simulation support
    public struct SimulatedService: Sendable { public let type: String; public let name: String; public let port: Int; public let hostname: String; public let ip: String; public let txt: [String:String]; public init(type: String, name: String, port: Int, hostname: String, ip: String, txt: [String:String] = [:]) { self.type = type; self.name = name; self.port = port; self.hostname = hostname; self.ip = ip; self.txt = txt } }
    private let simulated: [SimulatedService]?

    public init(resolveCooldown: TimeInterval = 12.0, dynamicBrowserCap: Int = 128, simulated: [SimulatedService]? = nil) {
        self.resolveCooldown = resolveCooldown
        self.dynamicBrowserCap = dynamicBrowserCap
        self.simulated = simulated
        super.init()
    }

    // Previous aggregation removed; provider now emits per-service devices.
    private func makeSingleServiceDevice(ips: [String], hostname: String?, service: NetworkService, serviceName: String, fingerprints: [String:String]) -> Device {
        // Stable primary IP preference: first IPv4 (lowest numerically) else first IPv6
        let ipv4s = ips.filter { $0.contains(".") }.sorted { a,b in
            let aP = a.split(separator: ".").compactMap { Int($0) }
            let bP = b.split(separator: ".").compactMap { Int($0) }
            for (x,y) in zip(aP,bP) { if x != y { return x < y } }
            return a < b
        }
        let primary = ipv4s.first(where: { !$0.hasPrefix("127.") && !$0.hasPrefix("169.254.") }) ?? ipv4s.first ?? ips.first
        let sanitizedIPs = ips.filter { !$0.hasPrefix("127.") && !$0.hasPrefix("169.254.") }
        let ipSet = sanitizedIPs.isEmpty ? Set(ips) : Set(sanitizedIPs)

        // Use serviceName as fallback hostname if hostname is nil or generic
        let displayHostname = hostname ?? serviceName
        // primary chosen above
        var vendor: String? = nil
        var model: String? = nil
        if !fingerprints.isEmpty {
            let vm = VendorModelExtractorService.extract(from: fingerprints)
            vendor = vm.vendor
            model = vm.model
        }
        return Device(primaryIP: primary, ips: ipSet, hostname: displayHostname, vendor: vendor, modelHint: model, discoverySources: [.mdns], services: [service], fingerprints: fingerprints, firstSeen: Date(), lastSeen: Date())
    }

    public func start(mutationBus: DeviceMutationBus) -> AsyncStream<DeviceMutation> {
        stopped = false
        return AsyncStream { continuation in
            // Check for test environment - disable real network discovery in tests
            let env = ProcessInfo.processInfo.environment
            let disableDiscovery = env["UNIFIEDSCANNER_DISABLE_NETWORK_DISCOVERY"] == "1"
            
            // Also check if we're running in test bundle
            let isRunningTests = Bundle.main.bundleURL.pathExtension == "xctest" || 
                                ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                                NSClassFromString("XCTest") != nil
            
            LoggingService.info("bonjour: environment check - UNIFIEDSCANNER_DISABLE_NETWORK_DISCOVERY=\(env["UNIFIEDSCANNER_DISABLE_NETWORK_DISCOVERY"] ?? "unset"), disabling=\(disableDiscovery), isRunningTests=\(isRunningTests)", category: .bonjour)
            if disableDiscovery || (isRunningTests && simulated == nil) {
                LoggingService.info("bonjour: network discovery disabled (envVar=\(disableDiscovery), testContext=\(isRunningTests))", category: .bonjour)
                continuation.finish()
                return
            }
            
            if let simulated = self.simulated {
                Task { [weak self] in
                    guard let self else { return }
                    for sim in simulated {
                        if self.stopped { break }
                            let svc = ServiceDeriver.makeService(fromRaw: sim.type, port: sim.port)
                            let dev = self.makeSingleServiceDevice(ips: [sim.ip], hostname: sim.hostname, service: svc, serviceName: sim.name, fingerprints: sim.txt)
                        let mutation = DeviceMutation.change(DeviceChange(before: nil, after: dev, changed: Set(DeviceField.allCases), source: .mdns))
                        continuation.yield(mutation)
                    }
                    continuation.finish()
                }
                return
            }
            // Real network path: browse raw types then resolve
            LoggingService.info("bonjour: provider starting curated=\(self.curatedServiceTypes.count) dynamicCap=\(self.dynamicBrowserCap) cooldown=\(self.resolveCooldown)s", category: .bonjour)
            let initBrowsers = { [weak self] in
                guard let self else { return }
                let allCurated = self.curatedServiceTypes
                let browse = BonjourBrowseService(curatedServiceTypes: allCurated,
                                                  additionalIOSAllowedTypes: self.additionalIOSAllowedTypes,
                                                  dynamicBrowserCap: self.dynamicBrowserCap)
                let resolve = BonjourResolveService(resolveCooldown: self.resolveCooldown)
                self.browseService = browse
                self.resolveService = resolve
                let typeStream = browse.start()
                let resolvedStream = resolve.resolveStream(forTypes: typeStream)
                Task { [weak self] in
                    guard let self else { return }
                    for await rs in resolvedStream {
                        if self.stopped { break }
                        let service = ServiceDeriver.makeService(fromRaw: rs.rawType, port: rs.port)
        let dev = self.makeSingleServiceDevice(ips: rs.ips, hostname: rs.hostname, service: service, serviceName: rs.serviceName, fingerprints: rs.txt)
                        LoggingService.info("bonjour: yielding device primary=\(dev.primaryIP ?? "nil") hostname=\(dev.hostname ?? "nil") svcType=\(service.type.rawValue) port=\(service.port ?? -1) ips=\(dev.ips.count)", category: .bonjour)
                        let mutation = DeviceMutation.change(DeviceChange(before: nil, after: dev, changed: Set(DeviceField.allCases), source: .mdns))
                        continuation.yield(mutation)
                    }
                    continuation.finish()
                }
            }
            if Thread.isMainThread { initBrowsers() } else { DispatchQueue.main.sync(execute: initBrowsers) }
        }
    }

    public func stop() {
        stopped = true
        browseService?.stop(); browseService = nil
        resolveService?.stop(); resolveService = nil
        continuation?.finish(); continuation = nil
    }

    deinit { stop() }
}

// MARK: - Internal Implementation
extension BonjourDiscoveryProvider {
    private func makeDevice(from sim: SimulatedService) -> Device {
        let svc = ServiceDeriver.makeService(fromRaw: sim.type, port: sim.port)
        return Device(primaryIP: sim.ip, ips: [sim.ip], hostname: sim.hostname, discoverySources: [.mdns], services: [svc], fingerprints: sim.txt, firstSeen: Date(), lastSeen: Date())
    }
}

// MARK: - PingOrchestrator
public actor PingOrchestrator {
    private let pingService: PingService
    private let mutationBus: DeviceMutationBus
    private let maxConcurrent: Int
    private var active: Set<String> = []
    private var progress: ScanProgress?

    init(pingService: PingService, mutationBus: DeviceMutationBus, maxConcurrent: Int = 32, progress: ScanProgress? = nil) {
        self.pingService = pingService
        self.mutationBus = mutationBus
        self.maxConcurrent = maxConcurrent
        self.progress = progress
    }

    func currentProgress() -> ScanProgress? { progress }
#if DEBUG
    func attachProgressIfAbsent(_ p: ScanProgress) { if self.progress == nil { self.progress = p } }
#endif

    public func enqueue(hosts: [String], config: PingConfig) async {
        if let progress = self.progress {
            let current = await progress.getCurrentProgress()
            if !current.started { await progress.begin(total: hosts.count); LoggingService.debug("progress forcing start total=\(hosts.count)", category: .ping) }
            if current.total == 0 { LoggingService.warn("enqueue before progress total set hosts=\(hosts.count)", category: .ping) }
        } else { LoggingService.warn("enqueue without progress reference", category: .ping) }
        LoggingService.debug("enqueue batch size=\(hosts.count)", category: .ping)
        for host in hosts {
            LoggingService.debug("queue host=\(host)", category: .ping)
            await throttleIfNeeded()
            await launch(host: host, baseConfig: config)
        }
    }

    private func throttleIfNeeded() async {
        let activeCount = active.count
        if activeCount >= maxConcurrent {
            let maxConc = maxConcurrent
            LoggingService.debug("throttle waiting active=\(activeCount) max=\(maxConc)", category: .ping)
        }
        while active.count >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func launch(host: String, baseConfig: PingConfig) async {
        let beforeCount = active.count
        LoggingService.debug("launch start host=\(host) active(before)=\(beforeCount)", category: .ping)
        active.insert(host)
        let mutationBusRef = mutationBus
        let progressRef = progress
        Task { [pingService] in
            LoggingService.debug("creating stream for host=\(host)", category: .ping)
            let stream = await pingService.pingStream(config: PingConfig(host: host, count: baseConfig.count, interval: baseConfig.interval, timeoutPerPing: baseConfig.timeoutPerPing))
            var sawSuccessFlag = false
            var localMeasurementCount = 0
            for await m in stream {
                localMeasurementCount += 1
                let mc = localMeasurementCount
                LoggingService.debug("measurement #\(mc) host=\(host) status=\(m.status)", category: .ping)
                if case .success = m.status { sawSuccessFlag = true }

                // Emit raw ping measurement; SnapshotService will decide on device changes
                let mutationBus = mutationBusRef
                await MainActor.run {
                    mutationBus.emit(.ping(m))
                }
            }
            let finalCount = localMeasurementCount
            let success = sawSuccessFlag
            LoggingService.debug("stream complete host=\(host) sawSuccess=\(success) measurements=\(finalCount)", category: .ping)
            await self.didFinish(host: host, sawSuccess: success)
            if let progressRef, success { await progressRef.incrementSuccess() }
        }
    }


    private func didFinish(host: String, sawSuccess: Bool) async {
        active.remove(host)
        if let progress = progress {
            let current = await progress.getCurrentProgress()
            await progress.incrementCompleted()
            LoggingService.debug("didFinish host=\(host) completed=\(current.completed + 1)/\(current.total) success=\(sawSuccess) (was \(current.completed))", category: .ping)
            if current.total == 0 { LoggingService.warn("progress.totalHosts still 0 at didFinish (race condition)", category: .ping) }
        } else { LoggingService.warn("didFinish with no progress reference host=\(host)", category: .ping) }
    }
}

// MARK: - DiscoveryCoordinator
actor DiscoveryCoordinator {
    private var autoBonjourStarted = false
    private let store: SnapshotService
    private let pingOrchestrator: PingOrchestrator
    private let mutationBus: DeviceMutationBus
    private let providers: [DiscoveryProvider]
    private let hostEnumerator: HostEnumerator
    private let arpService: ARPService
    private var bonjourTasks: [Task<Void, Never>] = []
    private var scanTask: Task<Void, Never>? = nil
    private var providersRunning = false
    private var scanRunning = false

    init(store: SnapshotService,
         pingOrchestrator: PingOrchestrator,
         mutationBus: DeviceMutationBus,
         providers: [DiscoveryProvider],
         hostEnumerator: HostEnumerator = LocalSubnetEnumerator(),
         arpService: ARPService = ARPService()) {
        self.store = store
        self.pingOrchestrator = pingOrchestrator
        self.mutationBus = mutationBus
        self.providers = providers
        self.hostEnumerator = hostEnumerator
        self.arpService = arpService
    }

    func startBonjour() async {
        guard !providersRunning else { return }
        providersRunning = true
        bonjourTasks.removeAll()

        // Providers now emit mutations directly to the mutation bus

        for provider in providers {
            Task { await pingOrchestrator.currentProgress()?.setPhase(.mdnsWarmup) }
            let mutationStream = provider.start(mutationBus: mutationBus)
            let task = Task { [weak self] in
                guard let self else { return }
                for await mutation in mutationStream {
                    if Task.isCancelled { break }
                    // Forward the mutation to the mutation bus
                    await self.mutationBus.emit(mutation)
                }
                await self.cleanupFinishedBonjourTasks()
            }
            bonjourTasks.append(task)
        }
    }



    func stopBonjour() async {
        guard providersRunning else { return }
        providersRunning = false
        bonjourTasks.forEach { $0.cancel() }
        bonjourTasks.removeAll()
        providers.forEach { $0.stop() }
    }

    func startScan(pingHosts: [String],
                   pingConfig: PingConfig,
                   mdnsWarmupSeconds: Double = 1.0,
                   autoEnumerateIfEmpty: Bool = true,
                   maxAutoEnumeratedHosts: Int = 256) async {
        guard scanTask == nil else { return }
        scanRunning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.pingOrchestrator.currentProgress()?.reset()
                if mdnsWarmupSeconds > 0 {
                    try await Task.sleep(nanoseconds: UInt64(mdnsWarmupSeconds * 1_000_000_000))
                }
                try Task.checkCancellation()
                await self.runEnumerationAndPing(pingHosts: pingHosts,
                                                 pingConfig: pingConfig,
                                                 autoEnumerateIfEmpty: autoEnumerateIfEmpty,
                                                 maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
            } catch is CancellationError {
                await self.pingOrchestrator.currentProgress()?.reset()
            } catch {
                LoggingService.warn("scan task error: \(error)", category: .discovery)
            }
            await self.finishScan()
        }
    }

#if os(macOS)
    func startDiscoveryPipeline(maxAutoEnumeratedHosts: Int) async {
        await startBonjour()
        await startARPOnly(maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
    }
#else
    func startDiscoveryPipeline(pingHosts: [String],
                                pingConfig: PingConfig,
                                mdnsWarmupSeconds: Double,
                                autoEnumerateIfEmpty: Bool,
                                maxAutoEnumeratedHosts: Int) async {
        await startScan(pingHosts: pingHosts,
                         pingConfig: pingConfig,
                         mdnsWarmupSeconds: mdnsWarmupSeconds,
                         autoEnumerateIfEmpty: autoEnumerateIfEmpty,
                         maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
    }
#endif

    func stopScan() async {
        guard let task = scanTask else { return }
        scanRunning = false
        task.cancel()
        scanTask = nil
        await pingOrchestrator.currentProgress()?.reset()
    }

    func currentState() -> (bonjour: Bool, scanning: Bool) {
        (providersRunning, scanRunning)
    }
#if os(macOS)
    func startARPOnly(maxAutoEnumeratedHosts: Int) async {
        guard scanTask == nil else { return }
        scanRunning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.pingOrchestrator.currentProgress()?.reset()
                try Task.checkCancellation()
                await self.runEnumerationAndPing(pingHosts: [],
                                                 pingConfig: PingConfig(host: "arp-only", count: 1, interval: 1.0, timeoutPerPing: 1.0),
                                                 autoEnumerateIfEmpty: false,
                                                 maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
            } catch is CancellationError {
                await self.pingOrchestrator.currentProgress()?.reset()
            } catch {
                LoggingService.warn("arp-only task error: \(error)", category: .arp)
            }
            await self.finishScan()
        }
    }
#endif
}

// MARK: - Internal helper
private extension DiscoveryCoordinator {
    func runEnumerationAndPing(pingHosts: [String], pingConfig: PingConfig, autoEnumerateIfEmpty: Bool, maxAutoEnumeratedHosts: Int) async {
        guard !Task.isCancelled else { return }
        await self.pingOrchestrator.currentProgress()?.setPhase(.arpPriming)
#if os(macOS)
        // macOS: start Bonjour immediately after initial ARP seed if not already started
        if !providersRunning && !autoBonjourStarted {
            autoBonjourStarted = true
            await startBonjour()
        }
        let initialArp = await self.arpService.getMACAddresses(for: [])
        for (ip, mac) in initialArp {
            let device = Device(primaryIP: ip, ips: [ip], macAddress: mac, discoverySources: [.arp], firstSeen: Date(), lastSeen: Date())
            let mutation = DeviceMutation.change(DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .arp))
            await self.mutationBus.emit(mutation)
        }
#endif
        let hosts: [String]
        if pingHosts.isEmpty, autoEnumerateIfEmpty {
            await self.pingOrchestrator.currentProgress()?.setPhase(.enumerating)
            let enumerated = hostEnumerator.enumerate(maxHosts: maxAutoEnumeratedHosts)
            hosts = enumerated.isEmpty ? [] : enumerated
            LoggingService.info("auto-enumerated hosts count=\(hosts.count)", category: .discovery)
        } else { hosts = pingHosts }
        guard !Task.isCancelled else { return }
        LoggingService.info("starting ping batch size=\(hosts.count)", category: .ping)
        if let progress = await self.pingOrchestrator.currentProgress() {
            LoggingService.debug("progress.begin total=\(hosts.count)", category: .ping)
            await progress.begin(total: hosts.count)
            let current = await progress.getCurrentProgress()
            LoggingService.debug("progress after begin total=\(current.total) started=\(current.started)", category: .ping)
        }
        if hosts.isEmpty {
            await self.pingOrchestrator.currentProgress()?.setPhase(.arpPriming)
            LoggingService.info("no hosts enumerated; attempting ARP-only population", category: .arp)
#if os(macOS)
            let arpMap = await self.arpService.getMACAddresses(for: [])
            for (ip, mac) in arpMap {
                let device = Device(primaryIP: ip, ips: [ip], macAddress: mac, discoverySources: [.arp], firstSeen: Date(), lastSeen: Date())
                let mutation = DeviceMutation.change(DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .arp))
                await self.mutationBus.emit(mutation)
            }
            LoggingService.info("ARP-only population count=\(arpMap.count)", category: .arp)
#endif
            if let progress = await self.pingOrchestrator.currentProgress() { await MainActor.run { progress.finished = true } }
            return
        }
#if os(macOS)
        await self.pingOrchestrator.currentProgress()?.setPhase(.arpPriming)
        LoggingService.info("ARP-first seeding enabled", category: .arp)
        let preMap = await self.arpService.getMACAddresses(for: Set(hosts))
        for (ip, mac) in preMap {
            if let existing = await MainActor.run(body: { self.store.devices.first(where: { $0.primaryIP == ip || $0.ips.contains(ip) }) }) {
                var updated = existing
                if (updated.macAddress ?? "").isEmpty { updated.macAddress = mac }
                updated.discoverySources.insert(.arp)
                let changedFields: Set<DeviceField> = [.macAddress, .discoverySources]
                let mutation = DeviceMutation.change(DeviceChange(before: existing, after: updated, changed: changedFields, source: .arp))
                await self.mutationBus.emit(mutation)
            }
        }
#endif
        await self.pingOrchestrator.currentProgress()?.setPhase(.pinging)
        await self.pingOrchestrator.enqueue(hosts: hosts, config: pingConfig)
        LoggingService.debug("ping operations enqueued, waiting for completion before ARP table read", category: .ping)
        if let progress = await self.pingOrchestrator.currentProgress() {
            var current = await progress.getCurrentProgress()
            while !current.finished {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                current = await progress.getCurrentProgress()
            }
        }
        LoggingService.debug("reading ARP table", category: .arp)
#if os(macOS)
        await self.pingOrchestrator.currentProgress()?.setPhase(.arpRefresh)
        if !hosts.isEmpty { await self.arpService.populateCache(for: hosts) }
#endif
        let ipToMac = await self.arpService.getMACAddresses(for: Set(hosts), delaySeconds: 0.2)
        if !ipToMac.isEmpty {
            for (ip, mac) in ipToMac {
                if let existingDevice = await MainActor.run(body: { self.store.devices.first(where: { $0.primaryIP == ip || $0.ips.contains(ip) }) }) {
                    var updatedDevice = existingDevice
                    if (updatedDevice.macAddress ?? "").isEmpty { updatedDevice.macAddress = mac }
                    if !updatedDevice.discoverySources.contains(.arp) { updatedDevice.discoverySources.insert(.arp) }
                    let changedFields: Set<DeviceField> = [.macAddress, .discoverySources]
                    let mutation = DeviceMutation.change(DeviceChange(before: existingDevice, after: updatedDevice, changed: changedFields, source: .arp))
                    await self.mutationBus.emit(mutation)
                    LoggingService.debug("ARP merged host=\(ip) mac=\(mac)", category: .arp)
                }
            }
        }
        for host in hosts {
            guard let mac = ipToMac[host] else { continue }
            let exists = await MainActor.run { self.store.devices.contains(where: { $0.primaryIP == host || $0.ips.contains(host) }) }
            if !exists {
                let device = Device(primaryIP: host, ips: [host], macAddress: mac, discoverySources: [.arp], firstSeen: Date(), lastSeen: Date())
                let mutation = DeviceMutation.change(DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .arp))
                await self.mutationBus.emit(mutation)
                LoggingService.debug("created ARP-derived device host=\(host) mac=\(mac)", category: .arp)
            }
        }
    }

    func cleanupFinishedBonjourTasks() async {
        bonjourTasks.removeAll { $0.isCancelled }
    }

    func finishScan() async {
        // iOS/iPadOS: if Bonjour not started yet, auto start now after ping cycle
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS) || os(macCatalyst)
        if !providersRunning && !autoBonjourStarted {
            autoBonjourStarted = true
            await startBonjour()
        }
#endif
        scanRunning = false
        scanTask = nil
    }
}
