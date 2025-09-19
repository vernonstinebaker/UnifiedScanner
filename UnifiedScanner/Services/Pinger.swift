import Foundation

// MARK: - Pinger Core Types
public struct PingConfig: Sendable {
    public let host: String
    public let count: Int
    public let interval: TimeInterval
    public let timeoutPerPing: TimeInterval
    public let allowPartialResults: Bool
    public init(host: String, count: Int = 3, interval: TimeInterval = 1.0, timeoutPerPing: TimeInterval = 1.0, allowPartialResults: Bool = true) {
        self.host = host
        self.count = count
        self.interval = interval
        self.timeoutPerPing = timeoutPerPing
        self.allowPartialResults = allowPartialResults
    }
}

public enum PingStatus: Sendable, Equatable {
    case success(rttMillis: Double)
    case timeout
    case unreachable
    case error(String)
}

public struct PingMeasurement: Sendable, Equatable {
    public let host: String
    public let sequence: Int
    public let status: PingStatus
    public let timestamp: Date
    public init(host: String, sequence: Int, status: PingStatus, timestamp: Date = Date()) {
        self.host = host
        self.sequence = sequence
        self.status = status
        self.timestamp = timestamp
    }
}

public protocol Pinger: Sendable {
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement>
}

// MARK: - SystemPinger (macOS using /sbin/ping)
#if os(macOS)
public final class SystemPinger: Pinger {
    private static let infoLoggingEnabled: Bool = true // Temporarily enable for debugging
    public init() {}
    public func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        let host = config.host
        let count = config.count
        let interval = config.interval
        let timeout = max(1, Int(ceil(config.timeoutPerPing)))

        return AsyncStream { continuation in
            Task.detached {
                for seq in 0..<count {
                    if Task.isCancelled { break }
                    let status = await Self.singlePingStatus(host: host, timeoutSeconds: timeout)
                    let measurement = await MainActor.run { PingMeasurement(host: host, sequence: seq, status: status) }
                    continuation.yield(measurement)
                    if seq < count - 1 { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
                }
                continuation.finish()
            }
        }
    }

    private static func singlePingStatus(host: String, timeoutSeconds: Int) async -> PingStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                // Use /usr/bin/env ping for better compatibility
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["ping", "-c", "1", "-W", String(timeoutSeconds * 1000), host]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                // Add a timeout to the process execution itself
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds + 1)) {
                    if process.isRunning {
                        if infoLoggingEnabled { print("[Ping] terminating hung process for host=\(host)") }
                        process.terminate()
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if infoLoggingEnabled { print("[Ping] host=\(host) exit=\(process.terminationStatus) output=\(output.prefix(200))") }

                    // Check for successful ping (exit code 0 and contains timing info)
                    if process.terminationStatus == 0 {
                        if let range = output.range(of: "time=([0-9.]+) ms", options: .regularExpression) {
                            let match = output[range]
                            if let timeString = match.split(separator: "=").last?.split(separator: " ").first, let rtt = Double(timeString) {
                                if infoLoggingEnabled { print("[Ping] host=\(host) success rtt=\(rtt)ms") }
                                continuation.resume(returning: .success(rttMillis: rtt))
                                return
                            }
                        }
                        // If exit code is 0 but no timing info, still consider it success with default RTT
                        if infoLoggingEnabled { print("[Ping] host=\(host) success (no timing, using 1ms)") }
                        continuation.resume(returning: .success(rttMillis: 1.0))
                        return
                    }

                    // Check for specific failure cases
                    if output.contains(" 0 packets received") || output.contains("100.0% packet loss") {
                        if infoLoggingEnabled { print("[Ping] host=\(host) timeout (packet loss)") }
                        continuation.resume(returning: .timeout)
                        return
                    }

                    if infoLoggingEnabled { print("[Ping] host=\(host) timeout (exit=\(process.terminationStatus))") }
                    continuation.resume(returning: .timeout)
                } catch {
                    if infoLoggingEnabled { print("[Ping] host=\(host) error=\(error)") }
                    continuation.resume(returning: .timeout)
                }
            }
        }
    }
}
#endif

// MARK: - SimplePingKit wrapper (iOS) + Stub fallback
public enum PlatformPingerFactory {
    public static func make() -> Pinger {
        #if os(macOS)
        return NetworkPinger()  // Use Network framework to populate ARP table
        #else
        return SimplePingPinger()
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(macOS)
import Network

public final class NetworkPinger: Pinger {
    private static let infoLoggingEnabled: Bool = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
    public init() {}
    public func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        let host = config.host
        let count = config.count
        let interval = config.interval
        return AsyncStream { continuation in
            Task.detached {
                for seq in 0..<count {
                    if Task.isCancelled { break }
        let _ = Date()
                    let rtt: Double? = await Self.tcpProbe(host: host, timeout: config.timeoutPerPing)
                    let status: PingStatus
                    if let r = rtt { status = .success(rttMillis: r) } else { status = .timeout }
                    let m = await MainActor.run { PingMeasurement(host: host, sequence: seq, status: status, timestamp: Date()) }
                    continuation.yield(m)
                    if seq < count - 1 { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
                }
                continuation.finish()
            }
        }
    }

    private static func tcpProbe(host: String, timeout: TimeInterval) async -> Double? {
        // Try multiple common ports to maximize ARP table population
        // Prioritized by likelihood of response and speed
        let commonPorts = [80, 443, 22, 53, 445, 548] // HTTP, HTTPS, SSH, DNS, SMB, AFP
        let logging = infoLoggingEnabled

        for port in commonPorts {
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [] // Allow all interface types
            let start = Date()
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: params)

            let result: Double? = await withCheckedContinuation { continuation in
                let lock = NSLock()
                var resumed = false
            func finish(_ value: Double?) {
                    lock.lock(); defer { lock.unlock() }
                    if resumed { return }
                    resumed = true
                    if logging {
                        if let v = value {
                            print("[NetworkPing] port \(port) success host=\(host) rtt=\(String(format: "%.1f", v))ms")
                        } else {
                            print("[NetworkPing] port \(port) failed host=\(host)")
                        }
                    }
                    continuation.resume(returning: value)
                    connection.cancel()
                }

            connection.stateUpdateHandler = { (state: NWConnection.State) in
                    switch state {
                    case .ready:
                        let rtt = Date().timeIntervalSince(start) * 1000.0
                        finish(rtt)
                    case .failed, .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }

                connection.start(queue: .global())

                // Shorter timeout per port to try multiple ports quickly
                let portTimeout = min(timeout / Double(commonPorts.count), 0.3)
                DispatchQueue.global().asyncAfter(deadline: .now() + portTimeout) {
                    finish(nil)
                }
            }

            // If we get a successful connection on any port, return it
            if let rtt = result {
                return rtt
            }
        }

        // If no TCP ports succeeded, try UDP as fallback to populate ARP table
        if logging { print("[NetworkPing] trying UDP probe for host=\(host)") }
        return await udpProbe(host: host, timeout: timeout)
    }

    private static func udpProbe(host: String, timeout: TimeInterval) async -> Double? {
        let params = NWParameters.udp
        params.prohibitedInterfaceTypes = []
        let start = Date()
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: 53)!, using: params) // DNS port

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            func finish(_ value: Double?) {
                lock.lock(); defer { lock.unlock() }
                if resumed { return }
                resumed = true
                if infoLoggingEnabled {
                    if let v = value {
                        print("[NetworkPing] UDP success host=\(host) rtt=\(String(format: "%.1f", v))ms")
                    } else {
                        print("[NetworkPing] UDP failed host=\(host)")
                    }
                }
                continuation.resume(returning: value)
                connection.cancel()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let rtt = Date().timeIntervalSince(start) * 1000.0
                    finish(rtt)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: .global())

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }

    /// Send broadcast UDP packets to populate ARP table for subnet-wide device discovery
    public static func sendBroadcastUDP(for subnet: String, timeout: TimeInterval = 2.0) async {
        let logging = infoLoggingEnabled
        if logging { print("[NetworkPing] sending broadcast UDP for subnet=\(subnet)") }

        // Common ports that devices might respond to
        let broadcastPorts: [UInt16] = [137, 138, 1900, 5353, 3702] // NetBIOS, SSDP, mDNS, WS-Discovery

        // Calculate broadcast address (assuming /24 subnet)
        let broadcastAddress = calculateBroadcastAddress(for: subnet)

        if logging { print("[NetworkPing] broadcast address=\(broadcastAddress)") }

        await withTaskGroup(of: Void.self) { group in
            for port in broadcastPorts {
                group.addTask {
                    await sendUDPToBroadcast(address: broadcastAddress, port: port, timeout: timeout)
                }
            }
        }

        if logging { print("[NetworkPing] broadcast UDP complete") }
    }

    private static func sendUDPToBroadcast(address: String, port: UInt16, timeout: TimeInterval) async {
        let logging = infoLoggingEnabled
        let params = NWParameters.udp
        params.prohibitedInterfaceTypes = []

        guard let portEndpoint = NWEndpoint.Port(rawValue: port),
              let connection = try? NWConnection(host: NWEndpoint.Host(address), port: portEndpoint, using: params) else {
            if logging { print("[NetworkPing] failed to create broadcast connection to \(address):\(port)") }
            return
        }

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            func finish() {
                lock.lock(); defer { lock.unlock() }
                if resumed { return }
                resumed = true
                continuation.resume(returning: ())
                connection.cancel()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if logging { print("[NetworkPing] broadcast connection ready to \(address):\(port)") }
                    // Send a small packet to trigger ARP
                    connection.send(content: Data([0x00]), completion: .contentProcessed({ error in
                        if let error = error, logging {
                            print("[NetworkPing] broadcast send error to \(address):\(port): \(error)")
                        }
                        finish()
                    }))
                case .failed, .cancelled:
                    finish()
                default:
                    break
                }
            }

            connection.start(queue: .global())

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish()
            }
        }
    }

    private static func calculateBroadcastAddress(for subnet: String) -> String {
        // For a subnet like "192.168.1.0", return "192.168.1.255"
        let components = subnet.split(separator: ".")
        guard components.count == 4 else { return subnet }
        return "\(components[0]).\(components[1]).\(components[2]).255"
    }
}
#endif

public final class StubPinger: Pinger {
    public init() {}
    public func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        AsyncStream { continuation in
            Task.detached {
                for seq in 0..<config.count {
                    if Task.isCancelled { break }
                    let m = await MainActor.run { PingMeasurement(host: config.host, sequence: seq, status: .error("stub")) }
                    continuation.yield(m)
                }
                continuation.finish()
            }
        }
    }
}
