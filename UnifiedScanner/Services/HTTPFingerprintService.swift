import Foundation
import Security
#if canImport(CryptoKit)
import CryptoKit
#endif

private struct FingerprintKey: Hashable, Sendable {
    let deviceID: String
    let host: String
    let scheme: String
    let port: Int
}

private struct FingerprintTarget: Sendable {
    let device: Device
    let host: String
    let scheme: String
    let port: Int
}

private struct HTTPFingerprintResponse {
    let response: HTTPURLResponse
    let data: Data?
}

@MainActor
final class HTTPFingerprintService {

    private let mutationBus: DeviceMutationBus
    private var listenerTask: Task<Void, Never>?
    private var pending: Set<FingerprintKey> = []
    private var lastRun: [FingerprintKey: Date] = [:]
    private let cooldown: TimeInterval
    private let requestTimeout: TimeInterval

    init(mutationBus: DeviceMutationBus, cooldown: TimeInterval = 1800, requestTimeout: TimeInterval = 4.0) {
        self.mutationBus = mutationBus
        self.cooldown = cooldown
        self.requestTimeout = requestTimeout
    }

    func start() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.mutationBus.mutationStream(includeBuffered: false)
            for await mutation in stream {
                if Task.isCancelled { break }
                await self.handle(mutation: mutation)
            }
        }
    }

    func stop() {
        listenerTask?.cancel()
        listenerTask = nil
        pending.removeAll()
    }

    func rescan(devices: [Device], force: Bool = false) {
        for device in devices {
            guard let host = host(for: device) else { continue }
            process(device: device, host: host, force: force)
        }
    }

    private func handle(mutation: DeviceMutation) async {
        guard case .change(let change) = mutation else { return }
        let device = change.after
        guard let host = host(for: device) else { return }
        process(device: device, host: host, force: false)
    }

    private func process(device: Device, host: String, force: Bool) {
        let candidates = fingerprintTargets(for: device, host: host)
        guard !candidates.isEmpty else { return }

        for target in candidates {
            let key = FingerprintKey(deviceID: target.device.id, host: target.host, scheme: target.scheme, port: target.port)
            let requestTimeout = self.requestTimeout
            if pending.contains(key) { continue }
            if !force, let last = lastRun[key], Date().timeIntervalSince(last) < cooldown { continue }
            pending.insert(key)
            scheduleFingerprint(for: target, key: key, timeout: requestTimeout)
        }
    }

    private func scheduleFingerprint(for target: FingerprintTarget, key: FingerprintKey, timeout: TimeInterval) {
        Task.detached(priority: .background) { [weak self] in
            let entries = await HTTPFingerprinter(timeout: timeout).fingerprint(target: target)
            guard let self else { return }
            await self.handleFingerprintResult(entries: entries, for: target, key: key)
        }
    }

    private func handleFingerprintResult(entries: [String: String], for target: FingerprintTarget, key: FingerprintKey) {
        pending.remove(key)
        lastRun[key] = Date()
        guard !entries.isEmpty else { return }
        emitFingerprints(entries, for: target)
    }

    private func emitFingerprints(_ entries: [String: String], for target: FingerprintTarget) {
        var delta: [String: String] = [:]
        let existing = target.device.fingerprints ?? [:]
        for (key, value) in entries where existing[key] != value {
            delta[key] = value
        }
        guard !delta.isEmpty else { return }

        var updatedSources = target.device.discoverySources
        updatedSources.insert(.httpProbe)

        let now = Date()
        let update = Device(id: target.device.id,
                            primaryIP: target.device.primaryIP,
                            ips: target.device.ips,
                            hostname: target.device.hostname,
                            macAddress: target.device.macAddress,
                            vendor: target.device.vendor,
                            modelHint: target.device.modelHint,
                            classification: target.device.classification,
                            discoverySources: updatedSources,
                            rttMillis: nil,
                            services: [],
                            openPorts: [],
                            fingerprints: delta,
                            firstSeen: target.device.firstSeen,
                            lastSeen: now,
                            isOnlineOverride: target.device.isOnline ? target.device.isOnlineOverride : true)

        let changed: Set<DeviceField> = [.fingerprints, .discoverySources, .lastSeen]
        let change = DeviceChange(before: nil, after: update, changed: changed, source: .httpFingerprint)
        mutationBus.emit(.change(change))
    }

    private func fingerprintTargets(for device: Device, host: String) -> [FingerprintTarget] {
        var results: [FingerprintTarget] = []

        let openCandidates = device.openPorts.filter { $0.status == .open }
        for port in openCandidates {
            guard let scheme = scheme(for: port, services: device.services) else { continue }
            results.append(FingerprintTarget(device: device, host: host, scheme: scheme, port: port.number))
        }

        for service in device.services where service.type == .http || service.type == .https {
            guard let port = service.port else { continue }
            let scheme = service.type == .https ? "https" : "http"
            if !results.contains(where: { $0.port == port && $0.scheme == scheme }) {
                results.append(FingerprintTarget(device: device, host: host, scheme: scheme, port: port))
            }
        }

        return results
    }

    private func scheme(for port: Port, services: [NetworkService]) -> String? {
        let number = port.number
        let lowerName = port.serviceName.lowercased()
        if number == 443 || lowerName.contains("https") { return "https" }
        if number == 8443 { return "https" }
        if number == 80 || number == 8080 || number == 8008 || number == 8000 || lowerName.contains("http") { return "http" }
        let matchedService = services.first { svc in
            guard let svcPort = svc.port else { return false }
            return svcPort == number && (svc.type == .http || svc.type == .https)
        }
        if let matchedService {
            return matchedService.type == .https ? "https" : "http"
        }
        return nil
    }

    private func host(for device: Device) -> String? {
        if let hostname = device.hostname, !hostname.isEmpty { return hostname }
        if let best = device.bestDisplayIP { return best }
        if let primary = device.primaryIP { return primary }
        return nil
    }

}

private final class HTTPFingerprinter: NSObject, URLSessionDelegate {
    private final class Delegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        var serverTrust: SecTrust?

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                serverTrust = trust
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    private let timeout: TimeInterval

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func fingerprint(target: FingerprintTarget) async -> [String: String] {
        guard let url = buildURL(host: target.host, scheme: target.scheme, port: target.port) else { return [:] }
        let delegate = Delegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let result = await performRequest(session: session, url: url) else { return [:] }
        let response = result.response
        let bodyData = result.data
        var entries: [String: String] = [:]

        if let serverHeader = header("Server", in: response), !serverHeader.isEmpty {
            entries["http.server"] = serverHeader
        }
        if let realm = extractRealm(from: response), !realm.isEmpty {
            entries["http.realm"] = realm
        }

        if url.scheme == "https",
           let trust = delegate.serverTrust {
            if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
                if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first {
                    appendCertificateSubject(from: certificate, into: &entries)
                }
            } else if let certificate = SecTrustGetCertificateAtIndex(trust, 0) {
                appendCertificateSubject(from: certificate, into: &entries)
            }
        }

        if let title = extractHTMLTitle(bodyData: bodyData, response: response) {
            entries["http.title"] = title
        }

        if let faviconFingerprint = await fetchFavicon(for: target, baseURL: url, session: session) {
            entries["http.favicon.sha256"] = faviconFingerprint.hash
            entries["http.favicon.size"] = String(faviconFingerprint.size)
        }

        return entries
    }

    private func performRequest(session: URLSession, url: URL) async -> HTTPFingerprintResponse? {
        if let headResponse = await sendRequest(session: session, url: url, method: "HEAD") {
            if headResponse.response.statusCode == 405 || headResponse.response.statusCode == 501 {
                return await sendRequest(session: session, url: url, method: "GET")
            }
            return headResponse
        }
        return await sendRequest(session: session, url: url, method: "GET")
    }

    private func sendRequest(session: URLSession, url: URL, method: String) async -> HTTPFingerprintResponse? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("UnifiedScanner/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            return HTTPFingerprintResponse(response: http, data: data)
        } catch {
            return nil
        }
    }

    private func header(_ name: String, in response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: name)
    }

    private func extractRealm(from response: HTTPURLResponse) -> String? {
        guard let value = response.value(forHTTPHeaderField: "WWW-Authenticate") else { return nil }
        let components = value.components(separatedBy: ",")
        for component in components {
            if let range = component.range(of: "realm=\"") {
                let remainder = component[range.upperBound...]
                if let closing = remainder.firstIndex(of: "\"") {
                    return String(remainder[..<closing])
                }
            }
        }
        return nil
    }

    private func buildURL(host: String, scheme: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let defaultPort = (scheme == "https") ? 443 : 80
        if port != defaultPort {
            components.port = port
        }
        components.path = "/"
        return components.url
    }

    private func appendCertificateSubject(from certificate: SecCertificate, into entries: inout [String: String]) {
        let subject = SecCertificateCopySubjectSummary(certificate) as String?
        if let subject, !subject.isEmpty {
            entries["https.cert.cn"] = subject
        }
    }

    private func extractHTMLTitle(bodyData: Data?, response: HTTPURLResponse) -> String? {
        guard let data = bodyData, !data.isEmpty else { return nil }
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() else { return nil }
        guard contentType.contains("text/html") else { return nil }
        let limit = min(data.count, 16_384)
        guard let snippet = String(data: data.prefix(limit), encoding: .utf8) else { return nil }

        let lower = snippet.lowercased()
        guard let titleStart = lower.range(of: "<title") else { return nil }
        guard let closingTag = lower.range(of: "</title>", range: titleStart.upperBound..<lower.endIndex) else { return nil }

        let afterTag = snippet[titleStart.upperBound..<closingTag.lowerBound]
        guard let start = afterTag.firstIndex(of: ">") else { return nil }
        let titleText = afterTag[afterTag.index(after: start)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = titleText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func fetchFavicon(for target: FingerprintTarget, baseURL: URL, session: URLSession) async -> (hash: String, size: Int)? {
        guard target.scheme == "http" || target.scheme == "https" else { return nil }
        guard let faviconURL = buildFaviconURL(host: target.host, scheme: target.scheme, port: target.port) else { return nil }

        var request = URLRequest(url: faviconURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("UnifiedScanner/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode < 400, !data.isEmpty, data.count <= 131_072 else { return nil }
            guard let hash = sha256Base64(data) else { return nil }
            return (hash, data.count)
        } catch {
            return nil
        }
    }

    private func buildFaviconURL(host: String, scheme: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let defaultPort = (scheme == "https") ? 443 : 80
        if port != defaultPort { components.port = port }
        components.path = "/favicon.ico"
        return components.url
    }

    private func sha256Base64(_ data: Data) -> String? {
#if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
#else
        return data.base64EncodedString()
#endif
    }
}
