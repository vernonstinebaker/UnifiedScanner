@preconcurrency import Foundation

final class BonjourResolveService: NSObject, @unchecked Sendable {
    struct ResolvedService { let ips: [String]; let hostname: String?; let port: Int?; let rawType: String; let txt: [String:String] }

    private let resolveCooldown: TimeInterval
    private var lastResolved: [String: Date] = [:]
    private let stateQueue = DispatchQueue(label: "BonjourResolveService.state")
    private var stopped = false
    private var activeTypes: Set<String> = [] // ensure single browser per type
    private var pendingResolveKeys: Set<String> = [] // track unresolved service keys for timeout logging

    init(resolveCooldown: TimeInterval) { self.resolveCooldown = resolveCooldown }

    func resolveStream(forTypes types: AsyncStream<String>) -> AsyncStream<ResolvedService> {
        return AsyncStream { continuation in
            self.continuations.append(continuation)
            Task { [weak self] in
                guard let self else { return }
                for await type in types {
                    if self.stopped { break }
                    await self.startBrowser(for: type)
                }
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    @MainActor
    private func startBrowser(for type: String) {
        // Normalize: lowercase + ensure trailing dot to dedupe variants
        var candidate = type.lowercased()
        if !candidate.hasSuffix(".") { candidate += "." }
        let normalizedType = candidate
        // Some callers might accidentally omit protocol segment; guard to avoid useless browsers
        if !normalizedType.contains("._tcp.") && !normalizedType.contains("._udp.") {
            LoggingService.debug("resolve: reject non-canonical type=\(type) normalized=\(normalizedType)")
            return
        }
        let lower = normalizedType
        var shouldStart = false
        stateQueue.sync {
            if !activeTypes.contains(lower) { activeTypes.insert(lower); shouldStart = true }
        }
        guard shouldStart else {
            LoggingService.debug("resolve: skip duplicate browser type=\(normalizedType)")
            return
        }
        let create = { [weak self] in
            guard let self else { return }
            let browser = NetServiceBrowser()
            LoggingService.info("resolve: launching browser type=\(normalizedType) original=\(type) onMain=\(Thread.isMainThread)")
            browser.delegate = self
            browser.searchForServices(ofType: normalizedType, inDomain: "local.")
            LoggingService.info("resolve: started browser type=\(normalizedType)")
            self.activeBrowsers.append(browser)
        }
        create()
    }

    private var activeBrowsers: [NetServiceBrowser] = []
    private var continuations: [AsyncStream<ResolvedService>.Continuation] = []
    private var resolvingServices: [String: NetService] = [:] // retain services until resolved or failed

    func stop() {
        stateQueue.sync { stopped = true; activeTypes.removeAll() }
        for b in activeBrowsers { b.stop() }
        activeBrowsers.removeAll()
    }

    private func shouldResolve(_ service: NetService) -> Bool {
        let key = serviceKey(service)
        return stateQueue.sync {
            let now = Date()
            if let last = lastResolved[key], now.timeIntervalSince(last) < resolveCooldown { return false }
            lastResolved[key] = now
            return true
        }
    }

    private func serviceKey(_ s: NetService) -> String { "\(s.name).\(s.type)\(s.domain)" }

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
                    let ip = {
                        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        return String(decoding: bytes, as: UTF8.self)
                    }()
                    if !ip.isEmpty && !ipv4s.contains(ip) { ipv4s.append(ip) }
                } else if sa.sa_family == sa_family_t(AF_INET6) {
                    let addrIn6 = rawBuf.baseAddress!.assumingMemoryBound(to: sockaddr_in6.self).pointee
                    var addr6 = addrIn6.sin6_addr
                    var buf6 = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    inet_ntop(AF_INET6, &addr6, &buf6, socklen_t(INET6_ADDRSTRLEN))
                    let ip6 = {
                        let bytes = buf6.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        return String(decoding: bytes, as: UTF8.self)
                    }()
                    if !ip6.isEmpty && !ipv6s.contains(ip6) { ipv6s.append(ip6) }
                }
#endif
            }
        }
        return ipv4s + ipv6s
    }
}

@MainActor
extension BonjourResolveService: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        let name = service.name; let type = service.type; let domain = service.domain
        LoggingService.info("resolve: discovered service name=\(name) type=\(type) domain=\(domain) moreComing=\(moreComing)")
        let key = serviceKey(service)
        let retainedService = service
        stateQueue.sync { resolvingServices[key] = retainedService }
        if shouldResolve(service) {
            LoggingService.debug("resolve: initiating resolve name=\(name) type=\(type)")
            service.resolve(withTimeout: 5.0)
            let key = self.serviceKey(service)
            stateQueue.sync { _ = pendingResolveKeys.insert(key) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                guard let self else { return }
                let stillPending = self.stateQueue.sync { self.pendingResolveKeys.contains(key) }
                if stillPending && !self.stopped {
                    LoggingService.debug("resolve: timeout pending key=\(key) name=\(name) type=\(type)")
                }
            }
        } else {
            LoggingService.debug("resolve: cooldown skip name=\(name) type=\(type)")
        }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        LoggingService.warn("resolve: browser failed error=\(errorDict)")
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let key = serviceKey(sender)
        stateQueue.sync {
            _ = pendingResolveKeys.remove(key)
            resolvingServices.removeValue(forKey: key)
        }
        LoggingService.warn("resolve: didNotResolve name=\(sender.name) type=\(sender.type) error=\(errorDict)")
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !stopped else { return }
        let name = sender.name; let type = sender.type; let port = sender.port; let txtSize = sender.txtRecordData()?.count ?? 0
        let ips = extractIPs(from: sender)
        LoggingService.info("resolve: didResolve name=\(name) type=\(type) ips=\(ips) port=\(port) txtBytes=\(txtSize)")
        if ips.isEmpty { return }
        var txt: [String:String] = [:]
        if let data = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: data)
            for (k,v) in dict { txt[k] = String(data: v, encoding: .utf8) ?? v.map { String(format: "%02x", $0) }.joined() }
        }
        var hostname = sender.hostName
        if let h = hostname, h.hasSuffix(".") { hostname = String(h.dropLast()) }
        let key = serviceKey(sender)
        stateQueue.sync {
            _ = pendingResolveKeys.remove(key)
            resolvingServices.removeValue(forKey: key)
        }
        let record = ResolvedService(ips: ips, hostname: hostname, port: sender.port == 0 ? nil : sender.port, rawType: sender.type, txt: txt)
        for c in continuations { c.yield(record) }
    }
}
