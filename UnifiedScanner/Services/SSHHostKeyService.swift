import Foundation
import Network
#if canImport(CryptoKit)
import CryptoKit
#endif

struct SSHFingerprintKey: Hashable, Sendable {
    let deviceID: String
    let host: String
    let port: Int
}

struct SSHFingerprintTarget: Sendable {
    let device: Device
    let host: String
    let port: Int
}

protocol SSHHostKeyCollecting: Sendable {
    func collect(target: SSHFingerprintTarget, timeout: TimeInterval) async -> [String: String]
}

// MARK: - Default Collector

struct DefaultSSHHostKeyCollector: SSHHostKeyCollecting {
    func collect(target: SSHFingerprintTarget, timeout: TimeInterval) async -> [String: String] {
#if os(macOS)
        let keyscanPath = "/usr/bin/ssh-keyscan"
        guard FileManager.default.isExecutableFile(atPath: keyscanPath) else { return [:] }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: keyscanPath)
            process.arguments = ["-p", "\(target.port)", "-T", "\(max(Int(timeout), 1))", "-t", "rsa,ecdsa,ed25519", target.host]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            try process.run()

            let data = try await readOutput(pipe: stdout, timeout: timeout)
            process.terminate()

            guard let output = String(data: data, encoding: .utf8) else { return [:] }
            return parseOutput(output)
        } catch {
            return [:]
        }
#else
        _ = timeout
        return [:]
#endif
    }

#if os(macOS)
    private func readOutput(pipe: Pipe, timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var buffer = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                }
                return buffer
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func parseOutput(_ output: String) -> [String: String] {
        var results: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 3 else { continue }
            let algorithm = parts[1].lowercased()
            let keyData = parts[2]
            guard let fingerprint = sha256Fingerprint(base64: keyData) else { continue }
            let key = "ssh.hostkey.\(algorithm).sha256"
            results[key] = fingerprint
        }
        return results
    }

    private func sha256Fingerprint(base64: String) -> String? {
        guard let raw = Data(base64Encoded: base64) else { return nil }
#if canImport(CryptoKit)
        let digest = SHA256.hash(data: raw)
        return Data(digest).base64EncodedString()
#else
        return raw.base64EncodedString()
#endif
    }
#endif
}

// MARK: - SSH Host Key Service

@MainActor
final class SSHHostKeyService {
    private let mutationBus: DeviceMutationBus
    private let collector: SSHHostKeyCollecting
    private let cooldown: TimeInterval
    private let timeout: TimeInterval

    private var listenerTask: Task<Void, Never>?
    private var pending: Set<SSHFingerprintKey> = []
    private var lastRun: [SSHFingerprintKey: Date] = [:]

    init(mutationBus: DeviceMutationBus,
         collector: SSHHostKeyCollecting? = nil,
         cooldown: TimeInterval = 3600,
         timeout: TimeInterval = 3.0) {
        self.mutationBus = mutationBus
        self.collector = collector ?? DefaultSSHHostKeyCollector()
        self.cooldown = cooldown
        self.timeout = timeout
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
            guard let host = canonicalHost(for: device) else { continue }
            process(device: device, host: host, force: force)
        }
    }

    private func handle(mutation: DeviceMutation) async {
        guard case .change(let change) = mutation else { return }
        let device = change.after
        guard let host = canonicalHost(for: device) else { return }
        process(device: device, host: host, force: false)
    }

    private func process(device: Device, host: String, force: Bool) {
        let targets = sshTargets(for: device, host: host)
        for target in targets {
            let key = SSHFingerprintKey(deviceID: target.device.id, host: target.host, port: target.port)
            if pending.contains(key) { continue }
            if !force, let last = lastRun[key], Date().timeIntervalSince(last) < cooldown { continue }
            pending.insert(key)
            scheduleFingerprint(for: target, key: key)
        }
    }

    private func scheduleFingerprint(for target: SSHFingerprintTarget, key: SSHFingerprintKey) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let entries = await self.collector.collect(target: target, timeout: self.timeout)
            await self.handleResult(entries: entries, target: target, key: key)
        }
    }

    private func handleResult(entries: [String: String], target: SSHFingerprintTarget, key: SSHFingerprintKey) {
        pending.remove(key)
        lastRun[key] = Date()
        guard !entries.isEmpty else { return }

        var delta: [String: String] = [:]
        let existing = target.device.fingerprints ?? [:]
        for (fingerprintKey, value) in entries where existing[fingerprintKey] != value {
            delta[fingerprintKey] = value
        }
        guard !delta.isEmpty else { return }

        var updatedSources = target.device.discoverySources
        updatedSources.insert(.portScan)

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
        let change = DeviceChange(before: nil, after: update, changed: changed, source: .portScan)
        mutationBus.emit(.change(change))
    }

    private func canonicalHost(for device: Device) -> String? {
        if let host = device.hostname, !host.isEmpty { return host }
        if let ip = device.bestDisplayIP { return ip }
        if let primary = device.primaryIP { return primary }
        return nil
    }

    private func sshTargets(for device: Device, host: String) -> [SSHFingerprintTarget] {
        var ports: Set<Int> = []
        for port in device.openPorts where port.status == .open && port.transport.lowercased() == "tcp" {
            if port.number == 22 { ports.insert(port.number) }
        }
        for service in device.services where service.type == .ssh {
            if let port = service.port { ports.insert(port) }
        }
        return ports.map { SSHFingerprintTarget(device: device, host: host, port: $0) }
    }
}
