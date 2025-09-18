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
                    let measurement: PingMeasurement
                    if let result = await Self.singlePing(host: host, timeoutSeconds: timeout) {
                        measurement = await MainActor.run { PingMeasurement(host: host, sequence: seq, status: .success(rttMillis: result)) }
                    } else {
                        measurement = await MainActor.run { PingMeasurement(host: host, sequence: seq, status: .timeout) }
                    }
                    continuation.yield(measurement)
                    if seq < count - 1 { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
                }
                continuation.finish()
            }
        }
    }

    private static func singlePing(host: String, timeoutSeconds: Int) async -> Double? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-c", "1", "-t", String(timeoutSeconds), host]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    guard process.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    if let range = output.range(of: "time=([0-9.]+) ms", options: .regularExpression) {
                        let match = output[range]
                        if let timeString = match.split(separator: "=").last?.split(separator: " ").first,
                           let rtt = Double(timeString) {
                            continuation.resume(returning: rtt)
                            return
                        }
                    }
                    continuation.resume(returning: 0.0) // Alive but RTT parse failed
                } catch {
                    continuation.resume(returning: nil)
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
        return SystemPinger()
        #else
        return SimplePingPinger()
        #endif
    }
}

#if os(iOS) || os(tvOS)
import Network

public final class SimplePingPinger: Pinger {
    public init() {}
    public func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        let host = config.host
        let count = config.count
        let interval = config.interval
        return AsyncStream { continuation in
            Task.detached {
                for seq in 0..<count {
                    if Task.isCancelled { break }
                    let start = Date()
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
        let params = NWParameters.tcp
        let start = Date()
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 80, using: params)
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let rtt = Date().timeIntervalSince(start) * 1000.0
                    connection.cancel()
                    continuation.resume(returning: rtt)
                case .failed, .cancelled:
                    continuation.resume(returning: nil)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if connection.state != .ready {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
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
