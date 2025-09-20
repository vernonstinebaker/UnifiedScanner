import Foundation
import Combine
#if canImport(Darwin)
import Darwin
#endif

// MARK: - ScanProgress
actor ScanProgress: ObservableObject {
    enum Phase: String, CaseIterable { case idle, mdnsWarmup, enumerating, arpPriming, pinging, arpRefresh, complete }
    @MainActor @Published var phase: Phase = .idle
    @MainActor @Published var totalHosts: Int = 0
    @MainActor @Published var completedHosts: Int = 0
    @MainActor @Published var started: Bool = false
    @MainActor @Published var finished: Bool = false { didSet { if finished { Task { await setPhase(.complete) } } } }
    @MainActor @Published var successHosts: Int = 0

    private nonisolated func log(_ msg: String) { LoggingService.debug(msg) }

    func reset() async {
        await setPhase(.idle)
        await MainActor.run {
            log("reset (prev total=\(totalHosts) completed=\(completedHosts) success=\(successHosts))")
            totalHosts = 0; completedHosts = 0; successHosts = 0; started = false; finished = false
        }
    }
    func begin(total: Int) async {
        await setPhase(.pinging)
        await MainActor.run {
            log("begin total=\(total)")
            started = true; finished = false; completedHosts = 0; successHosts = 0; totalHosts = total
        }
    }
    func incrementCompleted() async {
        await MainActor.run {
            completedHosts += 1
            if completedHosts >= totalHosts && totalHosts > 0 { finished = true; log("finished (completed=\(completedHosts) total=\(totalHosts))") }
        }
    }
    func incrementSuccess() async { await MainActor.run { successHosts += 1 } }
    func getCurrentProgress() async -> (total: Int, completed: Int, success: Int, started: Bool, finished: Bool, phase: Phase) { await MainActor.run { (totalHosts, completedHosts, successHosts, started, finished, phase) } }
    func setPhase(_ newPhase: Phase) async { await MainActor.run { self.phase = newPhase } }
}

// MARK: - DiscoveryProvider Protocol
public protocol DiscoveryProvider: AnyObject, Sendable {
    var name: String { get }
    func start() -> AsyncStream<Device>
    func stop()
}

// MARK: - Mock Provider (used in tests/demo)
public final class MockMDNSProvider: @unchecked Sendable, DiscoveryProvider {
    public let name = "mock-mdns"
    private let cancelledLock = NSLock()
    private var _cancelled = false
    public init() {}
    private var cancelled: Bool { get { cancelledLock.lock(); defer { cancelledLock.unlock() }; return _cancelled } set { cancelledLock.lock(); defer { cancelledLock.unlock() }; _cancelled = newValue } }

    public func start() -> AsyncStream<Device> {
        cancelled = false
        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else { return }
                let samples = [
                    Device(primaryIP: "192.168.1.50", ips: ["192.168.1.50"], hostname: "apple-tv.local", discoverySources: [.mdns], services: []),
                    Device(primaryIP: "192.168.1.51", ips: ["192.168.1.51"], hostname: "printer.local", discoverySources: [.mdns], services: [])
                ]
                for dev in samples {
                    if Task.isCancelled || self.cancelled { break }
                    continuation.yield(dev)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                continuation.finish()
            }
        }
    }
    public func stop() { cancelled = true }
}

// MARK: - BonjourDiscoveryProvider
public final class BonjourDiscoveryProvider: NSObject, @unchecked Sendable, DiscoveryProvider {
    public let name = "bonjour-mdns"
    private let resolveCooldown: TimeInterval
    private let dynamicBrowserCap: Int
    private var stopped = false

    private var continuation: AsyncStream<Device>.Continuation?

    // Browsers & tracking
    private var serviceBrowsers: [NetServiceBrowser] = []
    private var wildcardBrowser: NetServiceBrowser?
    private var activeServiceTypes: Set<String> = [] // lowercased types like _http._tcp.
    private var lastResolved: [String: Date] = [:]

    private let stateQueue = DispatchQueue(label: "BonjourDiscoveryProvider.state")

    // Curated commonly useful service types (include trailing dot as NetService expects)
    private let curatedServiceTypes: [String] = [
        "_airplay._tcp.", "_raop._tcp.", "_ssh._tcp.", "_http._tcp.", "_https._tcp.",
        "_hap._tcp.", "_spotify-connect._tcp.", "_smb._tcp.", "_ipp._tcp.", "_printer._tcp.",
        "_rfb._tcp.", "_afpovertcp._tcp.", "_sftp-ssh._tcp."
    ]

    // Simulation support for tests / previews
    public struct SimulatedService: Sendable { public let type: String; public let name: String; public let port: Int; public let hostname: String; public let ip: String; public let txt: [String:String]; public init(type: String, name: String, port: Int, hostname: String, ip: String, txt: [String:String] = [:]) { self.type = type; self.name = name; self.port = port; self.hostname = hostname; self.ip = ip; self.txt = txt } }
    private let simulated: [SimulatedService]?

    public init(resolveCooldown: TimeInterval = 12.0, dynamicBrowserCap: Int = 64, simulated: [SimulatedService]? = nil) {
        self.resolveCooldown = resolveCooldown
        self.dynamicBrowserCap = dynamicBrowserCap
        self.simulated = simulated
        super.init()
    }

    public func start() -> AsyncStream<Device> {
        stopped = false
        return AsyncStream { continuation in
            self.continuation = continuation
            if let simulated = self.simulated { // Test / preview path
                Task { [weak self] in
                    for sim in simulated {
                        guard let self, !self.stopped else { break }
                        let device = self.makeDevice(from: sim)
                        continuation.yield(device)
                    }
                    continuation.finish()
                }
                return
            }
            // Real network path
            self.startCuratedBrowsers()
            self.startWildcardBrowser()
        }
    }

    public func stop() {
        stateQueue.sync { stopped = true }
        for b in serviceBrowsers { b.stop() }
        serviceBrowsers.removeAll()
        continuation?.finish(); continuation = nil
    }

    deinit { stop() }
}

// MARK: - Internal Implementation
extension BonjourDiscoveryProvider: NetServiceBrowserDelegate, NetServiceDelegate {
    private func startCuratedBrowsers() {
        for type in curatedServiceTypes { startBrowser(for: type) }
    }
    private func startWildcardBrowser() {
        let type = "_services._dns-sd._udp."
        let browser = NetServiceBrowser()
        browser.delegate = self
        wildcardBrowser = browser
        serviceBrowsers.append(browser)
        browser.searchForServices(ofType: type, inDomain: "local.")
        LoggingService.debug("bonjour: started wildcard browser type=\(type)")
    }

    private func startBrowser(for type: String) {
        let lower = type.lowercased()
        stateQueue.sync { _ = activeServiceTypes.insert(lower) }
        let browser = NetServiceBrowser()
        browser.delegate = self
        serviceBrowsers.append(browser)
        browser.searchForServices(ofType: type, inDomain: "local.")
        LoggingService.debug("bonjour: started browser type=\(type)")
    }

    // MARK: NetServiceBrowserDelegate
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // If this is the wildcard enumeration browser, the service.type is a discovered service type; spin up dedicated browser if not already
        if service.type == "_services._dns-sd._udp." { return } // ignore self reference
        if browserIsWildcard(browser), isServiceTypeEnumeration(service: service) {
            let newType = service.name.hasSuffix(".") ? service.name : service.name + "." // when enumerating types, name holds the regtype sans domain
            considerStartingDynamicBrowser(forRawDiscoveredType: newType)
            return
        }
        // Normal service discovery path
        service.delegate = self
        resolveIfNeeded(service)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        LoggingService.warn("bonjour: browser failed error=\(errorDict)")
    }
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) { LoggingService.debug("bonjour: browser stopped") }

    // MARK: Resolution
    private func resolveIfNeeded(_ service: NetService) {
        let key = serviceKey(service)
        let shouldResolve: Bool = stateQueue.sync {
            let now = Date()
            if let last = lastResolved[key], now.timeIntervalSince(last) < resolveCooldown { return false }
            lastResolved[key] = now
            return true
        }
        guard shouldResolve else { return }
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        // Copy needed fields early to avoid potential concurrency capture warnings
        let senderType = sender.type
        let senderPort = sender.port
        let senderHostName = sender.hostName
        guard !stopped else { return }
        let ips = extractIPs(from: sender)
        if ips.isEmpty { return }
        var fingerprints: [String:String] = [:]
        if let data = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: data)
            for (k,v) in dict { fingerprints[k] = String(data: v, encoding: .utf8) ?? v.map { String(format: "%02x", $0) }.joined() }
        }
        let rawType = senderType
        let svc = ServiceDeriver.makeService(fromRaw: rawType, port: senderPort == 0 ? nil : senderPort)
        var hostname = senderHostName
        if let h = hostname, h.hasSuffix(".") { hostname = String(h.dropLast()) }
        let device = Device(primaryIP: ips.first, ips: Set(ips), hostname: hostname, discoverySources: [.mdns], services: [svc], fingerprints: fingerprints, firstSeen: Date(), lastSeen: Date())
        continuation?.yield(device)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let name = sender.name
        let type = sender.type
        let errSummary = errorDict.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        LoggingService.debug("bonjour: resolve failed name=\(name) type=\(type) error=[\(errSummary)]")
    }

    // MARK: Helpers
    private func browserIsWildcard(_ browser: NetServiceBrowser) -> Bool {
        return browser === wildcardBrowser
    }

    private func isServiceTypeEnumeration(service: NetService) -> Bool {
        // When browsing _services._dns-sd._udp., NetService instances represent service types; heuristics: port=0 & no addresses yet.
        return service.port == -1 || service.port == 0 && service.name.hasPrefix("_") && service.type == "_services._dns-sd._udp."
    }

    private func considerStartingDynamicBrowser(forRawDiscoveredType type: String) {
        let normalized = type.lowercased()
        stateQueue.sync {
            guard activeServiceTypes.count < dynamicBrowserCap else { return }
            if !activeServiceTypes.contains(normalized) {
                activeServiceTypes.insert(normalized)
                DispatchQueue.main.async { [weak self] in self?.startBrowser(for: type) }
            }
        }
    }

    private func serviceKey(_ s: NetService) -> String { "\(s.name).\(s.type)\(s.domain)" }

    private func stringFromCStringBuffer(_ buf: [CChar]) -> String {
        if let nul = buf.firstIndex(of: 0) {
            let bytes = buf[..<nul].map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
        return String(decoding: buf.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func extractIPs(from service: NetService) -> [String] {
        guard let datas = service.addresses else { return [] }
        var ipv4s: [String] = []
        var ipv6s: [String] = []
        for data in datas {
            data.withUnsafeBytes { rawBuf in
                guard rawBuf.count >= MemoryLayout<sockaddr>.size else { return }
                let sa = rawBuf.baseAddress!.assumingMemoryBound(to: sockaddr.self).pointee
                #if canImport(Darwin)
                if sa.sa_family == sa_family_t(AF_INET) {
                    let addrIn = rawBuf.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                    var addr = addrIn.sin_addr
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                    let ip = stringFromCStringBuffer(buf)
                    if !ip.isEmpty && !ipv4s.contains(ip) { ipv4s.append(ip) }
                } else if sa.sa_family == sa_family_t(AF_INET6) {
                    let addrIn6 = rawBuf.baseAddress!.assumingMemoryBound(to: sockaddr_in6.self).pointee
                    var addr6 = addrIn6.sin6_addr
                    var buf6 = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    inet_ntop(AF_INET6, &addr6, &buf6, socklen_t(INET6_ADDRSTRLEN))
                    let ip6 = stringFromCStringBuffer(buf6)
                    if !ip6.isEmpty && !ipv6s.contains(ip6) { ipv6s.append(ip6) }
                }
                #endif
            }
        }
        return ipv4s + ipv6s
    }

    private func makeDevice(from sim: SimulatedService) -> Device {
        let svc = ServiceDeriver.makeService(fromRaw: sim.type, port: sim.port)
        return Device(primaryIP: sim.ip, ips: [sim.ip], hostname: sim.hostname, discoverySources: [.mdns], services: [svc], fingerprints: sim.txt, firstSeen: Date(), lastSeen: Date())
    }
}

// MARK: - PingOrchestrator
public actor PingOrchestrator {
    private let pingService: PingService
    private let store: SnapshotService
    private let maxConcurrent: Int
    private var active: Set<String> = []
    private var progress: ScanProgress?

    init(pingService: PingService, store: SnapshotService, maxConcurrent: Int = 32, progress: ScanProgress? = nil) {
        self.pingService = pingService
        self.store = store
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
            if !current.started { await progress.begin(total: hosts.count); LoggingService.debug("progress forcing start total=\(hosts.count)") }
            if current.total == 0 { LoggingService.warn("enqueue before progress total set hosts=\(hosts.count)") }
        } else { LoggingService.warn("enqueue without progress reference") }
        LoggingService.debug("enqueue batch size=\(hosts.count)")
        for host in hosts {
            LoggingService.debug("queue host=\(host)")
            await throttleIfNeeded()
            await launch(host: host, baseConfig: config)
        }
    }

    private func throttleIfNeeded() async {
        let activeCount = active.count
        if activeCount >= maxConcurrent {
            let maxConc = maxConcurrent
            LoggingService.debug("throttle waiting active=\(activeCount) max=\(maxConc)")
        }
        while active.count >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func launch(host: String, baseConfig: PingConfig) async {
        let beforeCount = active.count
        LoggingService.debug("launch start host=\(host) active(before)=\(beforeCount)")
        active.insert(host)
        let storeRef = store
        let progressRef = progress
        Task { [pingService] in
            LoggingService.debug("creating stream for host=\(host)")
            let stream = await pingService.pingStream(config: PingConfig(host: host, count: baseConfig.count, interval: baseConfig.interval, timeoutPerPing: baseConfig.timeoutPerPing))
            var sawSuccessFlag = false
            var localMeasurementCount = 0
            for await m in stream {
                localMeasurementCount += 1
                let mc = localMeasurementCount
                LoggingService.debug("measurement #\(mc) host=\(host) status=\(m.status)")
                if case .success = m.status { sawSuccessFlag = true }
                await storeRef.applyPing(m)
            }
            let finalCount = localMeasurementCount
            let success = sawSuccessFlag
            LoggingService.debug("stream complete host=\(host) sawSuccess=\(success) measurements=\(finalCount)")
            await self.didFinish(host: host, sawSuccess: success)
            if let progressRef, success { await progressRef.incrementSuccess() }
        }
    }

    private func didFinish(host: String, sawSuccess: Bool) async {
        active.remove(host)
        if let progress = progress {
            let current = await progress.getCurrentProgress()
            await progress.incrementCompleted()
            LoggingService.debug("didFinish host=\(host) completed=\(current.completed + 1)/\(current.total) success=\(sawSuccess) (was \(current.completed))")
            if current.total == 0 { LoggingService.warn("progress.totalHosts still 0 at didFinish (race condition)") }
        } else { LoggingService.warn("didFinish with no progress reference host=\(host)") }
    }
}

// MARK: - DiscoveryCoordinator
actor DiscoveryCoordinator {
    private let store: SnapshotService
    private let pingOrchestrator: PingOrchestrator
    private let providers: [DiscoveryProvider]
    private let hostEnumerator: HostEnumerator
    private let arpService: ARPService
    private var tasks: [Task<Void, Never>] = []
    private var started = false

    init(store: SnapshotService, pingOrchestrator: PingOrchestrator, providers: [DiscoveryProvider], hostEnumerator: HostEnumerator = LocalSubnetEnumerator(), arpService: ARPService = ARPService()) {
        self.store = store
        self.pingOrchestrator = pingOrchestrator
        self.providers = providers
        self.hostEnumerator = hostEnumerator
        self.arpService = arpService
    }

    func start(pingHosts: [String], pingConfig: PingConfig, mdnsWarmupSeconds: Double = 2.0, autoEnumerateIfEmpty: Bool = true, maxAutoEnumeratedHosts: Int = 256) {
        internalStart(pingHosts: pingHosts, pingConfig: pingConfig, mdnsWarmupSeconds: mdnsWarmupSeconds, autoEnumerateIfEmpty: autoEnumerateIfEmpty, maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
    }

    private func internalStart(pingHosts: [String], pingConfig: PingConfig, mdnsWarmupSeconds: Double, autoEnumerateIfEmpty: Bool, maxAutoEnumeratedHosts: Int) {
        guard !started else { return }
        started = true
        for provider in providers {
            Task { await self.pingOrchestrator.currentProgress()?.setPhase(.mdnsWarmup) }
            let stream = provider.start()
            let t = Task { for await dev in stream { await self.store.upsert(dev, source: .mdns) } }
            tasks.append(t)
        }
        let t = Task { [pingHosts, pingConfig, autoEnumerateIfEmpty, maxAutoEnumeratedHosts] in
            try? await Task.sleep(nanoseconds: UInt64(mdnsWarmupSeconds * 1_000_000_000))
            await self.runEnumerationAndPing(pingHosts: pingHosts, pingConfig: pingConfig, autoEnumerateIfEmpty: autoEnumerateIfEmpty, maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
        }
        tasks.append(t)
    }

    func startAndWait(pingHosts: [String], pingConfig: PingConfig, mdnsWarmupSeconds: Double = 2.0, autoEnumerateIfEmpty: Bool = true, maxAutoEnumeratedHosts: Int = 256, waitTimeoutSeconds: Double = 5.0) async {
        internalStart(pingHosts: pingHosts, pingConfig: pingConfig, mdnsWarmupSeconds: mdnsWarmupSeconds, autoEnumerateIfEmpty: autoEnumerateIfEmpty, maxAutoEnumeratedHosts: maxAutoEnumeratedHosts)
        let deadline = Date().addingTimeInterval(waitTimeoutSeconds)
        while Date() < deadline {
            if let progress = await pingOrchestrator.currentProgress() {
                let current = await progress.getCurrentProgress()
                if current.finished || (current.total == 0 && current.started) { break }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func stop() { for t in tasks { t.cancel() }; tasks.removeAll() }
}

// MARK: - Internal helper
private extension DiscoveryCoordinator {
    func runEnumerationAndPing(pingHosts: [String], pingConfig: PingConfig, autoEnumerateIfEmpty: Bool, maxAutoEnumeratedHosts: Int) async {
        await self.pingOrchestrator.currentProgress()?.setPhase(.arpPriming)
#if os(macOS)
        let initialArp = await self.arpService.getMACAddresses(for: [])
        for (ip, mac) in initialArp {
            let device = Device(primaryIP: ip, ips: [ip], macAddress: mac, discoverySources: [.arp], firstSeen: Date(), lastSeen: Date())
            await self.store.upsert(device, source: .arp)
        }
#endif
        let hosts: [String]
        if pingHosts.isEmpty, autoEnumerateIfEmpty {
            await self.pingOrchestrator.currentProgress()?.setPhase(.enumerating)
            let enumerated = hostEnumerator.enumerate(maxHosts: maxAutoEnumeratedHosts)
            hosts = enumerated.isEmpty ? [] : enumerated
            LoggingService.info("auto-enumerated hosts count=\(hosts.count)")
        } else { hosts = pingHosts }
        LoggingService.info("starting ping batch size=\(hosts.count)")
        if let progress = await self.pingOrchestrator.currentProgress() {
            LoggingService.debug("progress.begin total=\(hosts.count)")
            await progress.begin(total: hosts.count)
            let current = await progress.getCurrentProgress()
            LoggingService.debug("progress after begin total=\(current.total) started=\(current.started)")
        }
        if hosts.isEmpty {
            await self.pingOrchestrator.currentProgress()?.setPhase(.arpPriming)
            LoggingService.info("no hosts enumerated; attempting ARP-only population")
#if os(macOS)
            let arpMap = await self.arpService.getMACAddresses(for: [])
            for (ip, mac) in arpMap {
                let device = Device(primaryIP: ip, ips: [ip], macAddress: mac, discoverySources: [.arp], firstSeen: Date(), lastSeen: Date())
                await self.store.upsert(device, source: .arp)
            }
            LoggingService.info("ARP-only population count=\(arpMap.count)")
#endif
            if let progress = await self.pingOrchestrator.currentProgress() { await MainActor.run { progress.finished = true } }
            return
        }
#if os(macOS)
        await self.pingOrchestrator.currentProgress()?.setPhase(.arpPriming)
        LoggingService.info("ARP-first seeding enabled")
        let preMap = await self.arpService.getMACAddresses(for: Set(hosts))
        for (ip, mac) in preMap {
            if let existing = await MainActor.run(body: { self.store.devices.first(where: { $0.primaryIP == ip || $0.ips.contains(ip) }) }) {
                var updated = existing
                if (updated.macAddress ?? "").isEmpty { updated.macAddress = mac }
                updated.discoverySources.insert(.arp)
                await self.store.upsert(updated, source: .arp)
            }
        }
#endif
        await self.pingOrchestrator.currentProgress()?.setPhase(.pinging)
        await self.pingOrchestrator.enqueue(hosts: hosts, config: pingConfig)
        LoggingService.debug("ping operations enqueued, waiting for completion before ARP table read")
        if let progress = await self.pingOrchestrator.currentProgress() {
            var current = await progress.getCurrentProgress()
            while !current.finished {
                try? await Task.sleep(nanoseconds: 500_000_000)
                current = await progress.getCurrentProgress()
            }
        }
        LoggingService.debug("reading ARP table")
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
                    await self.store.upsert(updatedDevice, source: .arp)
                    LoggingService.debug("ARP merged host=\(ip) mac=\(mac)")
                }
            }
        }
        for host in hosts {
            guard let mac = ipToMac[host] else { continue }
            let exists = await MainActor.run { self.store.devices.contains(where: { $0.primaryIP == host || $0.ips.contains(host) }) }
            if !exists {
                let device = Device(primaryIP: host, ips: [host], macAddress: mac, discoverySources: [.arp], firstSeen: Date(), lastSeen: Date())
                await self.store.upsert(device, source: .arp)
                LoggingService.debug("created ARP-derived device host=\(host) mac=\(mac)")
            }
        }
    }
}