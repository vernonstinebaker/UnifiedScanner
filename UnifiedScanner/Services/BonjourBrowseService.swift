import Foundation

final class BonjourBrowseService: NSObject, @unchecked Sendable {
    let curatedServiceTypes: [String]
    let dynamicBrowserCap: Int
    private var activeServiceTypes: Set<String> = [] // tracks browsers started (curated + dynamic)
    private var emittedServiceTypes: Set<String> = [] // tracks types already emitted downstream
    private var serviceBrowsers: [NetServiceBrowser] = []
    private var wildcardBrowser: NetServiceBrowser?
    private let stateQueue = DispatchQueue(label: "BonjourBrowseService.state")
    private var stopped = false

    static let validTypeRegex: NSRegularExpression = {
        // _name._tcp.  or _name._udp. (allow alnum + dash)
        return try! NSRegularExpression(pattern: "^_[A-Za-z0-9-]+\\._(tcp|udp)\\.$")
    }()

    let permittedTypesIOS: Set<String>

    init(curatedServiceTypes: [String], dynamicBrowserCap: Int) {
        self.curatedServiceTypes = curatedServiceTypes
        self.dynamicBrowserCap = dynamicBrowserCap
        let fixedIOS = [
            "_services._dns-sd._udp.",
            "_companion-link._tcp.",
            "_device-info._tcp.",
            "_remotepairing._tcp.",
            "_apple-mobdev2._tcp.",
            "_touch-able._tcp.",
            "_sleep-proxy._udp.",
            "_workstation._tcp.",
            "_afp._tcp."
        ]
#if os(iOS)
        self.permittedTypesIOS = Set((curatedServiceTypes + fixedIOS).map { $0.lowercased() })
#else
        self.permittedTypesIOS = Set(curatedServiceTypes.map { $0.lowercased() })
#endif
    }

    func start() -> AsyncStream<String> { // emits raw service types (e.g. _http._tcp.)
        stopped = false
        // Reset tracking sets for a fresh run
        stateQueue.sync {
            activeServiceTypes.removeAll()
            emittedServiceTypes.removeAll()
        }
        let launch = { [weak self] in
            guard let self else { return }
            self.startCuratedBrowsers()
            self.startWildcardBrowser()
            LoggingService.info("browse: browsers started onMain=\(Thread.isMainThread)", category: .bonjour)
        }
        // Enforce synchronous creation on main thread
        if Thread.isMainThread { launch() } else { DispatchQueue.main.sync(execute: launch) }
        return AsyncStream { [weak self] continuation in
            guard let strongSelf = self else { return }
            strongSelf.onNewType = { t in continuation.yield(t) }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    private var onNewType: ((String) -> Void)?

    func stop() {
        stateQueue.sync { stopped = true }
        for b in serviceBrowsers { b.stop() }
        serviceBrowsers.removeAll()
    }
}

extension BonjourBrowseService: NetServiceBrowserDelegate {
    static func isValidServiceType(_ type: String) -> Bool {
        let range = NSRange(location: 0, length: type.utf16.count)
        return Self.validTypeRegex.firstMatch(in: type, options: [], range: range) != nil
    }

    func emitTypeIfNeeded(_ type: String, origin: String) {
        let lower = type.lowercased()
#if os(iOS)
        guard permittedTypesIOS.contains(lower) else {
            LoggingService.debug("browse: skipping type not declared for iOS origin=\(origin) type=\(type)", category: .bonjour)
            return
        }
#endif
        var shouldEmit = false
        stateQueue.sync {
            if !emittedServiceTypes.contains(lower) {
                emittedServiceTypes.insert(lower)
                shouldEmit = true
            }
        }
        if shouldEmit {
            LoggingService.info("browse: emitting serviceType=\(type) origin=\(origin)", category: .bonjour)
            onNewType?(type)
        } else {
            LoggingService.debug("browse: skip duplicate emission type=\(type) origin=\(origin)", category: .bonjour)
        }
    }

    func startCuratedBrowsers() {
        LoggingService.info("browse: starting curated browsers count=\(self.curatedServiceTypes.count)", category: .bonjour)
        for type in curatedServiceTypes { startBrowser(for: type) }
        LoggingService.info("browse: curated browsers started activeCount=\(self.serviceBrowsers.count)", category: .bonjour)
    }
    func startWildcardBrowser() {
        let type = "_services._dns-sd._udp."
        let browser = NetServiceBrowser()
        browser.delegate = self
        wildcardBrowser = browser
        serviceBrowsers.append(browser)
        browser.searchForServices(ofType: type, inDomain: "local.")
        LoggingService.info("browse: started wildcard browser type=\(type)", category: .bonjour)
    }
    func startBrowser(for type: String) {
        let lower = type.lowercased()
        stateQueue.sync { _ = activeServiceTypes.insert(lower) }
        let browser = NetServiceBrowser()
        browser.delegate = self
        serviceBrowsers.append(browser)
        browser.searchForServices(ofType: type, inDomain: "local.")
        LoggingService.info("browse: started browser type=\(type)", category: .bonjour)
    }
    func browserIsWildcard(_ browser: NetServiceBrowser) -> Bool { browser === wildcardBrowser }
    func isServiceTypeEnumeration(service: NetService) -> Bool {
        return (service.port == -1 || service.port == 0) && service.name.hasPrefix("_") && service.type == "_services._dns-sd._udp."
    }
    private func considerStartingDynamicBrowser(forRawDiscoveredType type: String) {
        let normalized = type.lowercased()
#if os(iOS)
        guard permittedTypesIOS.contains(normalized) else {
            LoggingService.debug("browse: iOS skipping dynamic browser for undeclared type=\(type)", category: .bonjour)
            return
        }
#endif
        stateQueue.sync {
            guard self.activeServiceTypes.count < self.dynamicBrowserCap else { LoggingService.debug("browse: dynamic cap reached cap=\(self.dynamicBrowserCap) skipping type=\(normalized)", category: .bonjour); return }
            if !activeServiceTypes.contains(normalized) {
                self.activeServiceTypes.insert(normalized)
                LoggingService.info("browse: starting dynamic browser type=\(type) activeDynamic=\(self.activeServiceTypes.count) cap=\(self.dynamicBrowserCap)", category: .bonjour)
                if Thread.isMainThread { self.startBrowser(for: type) } else { DispatchQueue.main.async { [weak self] in self?.startBrowser(for: type) } }
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if service.type == "_services._dns-sd._udp." { return }
        if browserIsWildcard(browser), isServiceTypeEnumeration(service: service) {
            let newType = service.name.hasSuffix(".") ? service.name : service.name + "."
            LoggingService.debug("browse: wildcard discovered rawType=\(newType) moreComing=\(moreComing)", category: .bonjour)
            if Self.isValidServiceType(newType) {
                considerStartingDynamicBrowser(forRawDiscoveredType: newType)
                emitTypeIfNeeded(newType, origin: "wildcard")
            } else {
                LoggingService.info("browse: ignoring invalidType=\(newType)", category: .bonjour)
            }
            return
        }
        // Normal service instance discovery path
        let rawType = service.type
        if !rawType.isEmpty && Self.isValidServiceType(rawType) {
            emitTypeIfNeeded(rawType, origin: "instance")
        } else if !rawType.isEmpty {
            LoggingService.debug("browse: invalid instance type=\(rawType)", category: .bonjour)
        }
    }
}
