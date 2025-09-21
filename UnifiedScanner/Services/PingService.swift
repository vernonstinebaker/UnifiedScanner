import Foundation
import SimplePingKit

typealias SimplePingClient = SimplePingKit.PingService

public struct PingConfig: Sendable {
    public let host: String
    public let count: Int
    public let interval: TimeInterval
    public let timeoutPerPing: TimeInterval
    public let payloadSize: Int

    public init(host: String,
                count: Int = 1,
                interval: TimeInterval = 1.0,
                timeoutPerPing: TimeInterval = 1.5,
                payloadSize: Int = 32) {
        self.host = host
        self.count = max(1, count)
        self.interval = max(0.2, interval)
        self.timeoutPerPing = max(0.5, timeoutPerPing)
        self.payloadSize = max(0, payloadSize)
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

public protocol PingService: Sendable {
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement>
}



public final class SimplePingKitService: PingService {
    public init() {}

    public func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        let logging = true
        return AsyncStream { continuation in
            let coordinator = SimplePingStreamCoordinator(continuation: continuation, logging: logging, config: config)

            continuation.onTermination = { _ in
                Task { await coordinator.finish() }
            }

            Task {
                await coordinator.start()
            }
        }
    }
}

private actor SimplePingStreamCoordinator {
    private let continuation: AsyncStream<PingMeasurement>.Continuation
    private let logging: Bool
    private let config: PingConfig
    private var finished = false
    private var client: SimplePingClient?

    init(continuation: AsyncStream<PingMeasurement>.Continuation, logging: Bool, config: PingConfig) {
        self.continuation = continuation
        self.logging = logging
        self.config = config
    }

    func start() async {
        let config = self.config
        let logging = self.logging
        let actor = self

        let (client, configurationDescription) = await MainActor.run { () -> (SimplePingClient, String) in
            let client = SimplePingClient()
            let configuration = PingConfiguration(
                host: self.config.host,
                payloadSize: config.payloadSize,
                interval: config.interval,
                timeout: config.timeoutPerPing,
                maximumPings: config.count
            )

            let description = String(format: "[SimplePing] start host=%@ count=%d interval=%.2f timeout=%.2f", config.host, config.count, config.interval, config.timeoutPerPing)
            client.start(
                configuration: configuration,
                onStateChange: { state in
                    Task { await actor.handleStateChange(state) }
                },
                onEvent: { event in
                    Task { await actor.handleEvent(event) }
                }
            )

            return (client, description)
        }

        if logging { LoggingService.debug(configurationDescription, category: .ping) }
        self.client = client
    }

    func finish() async {
        guard !finished else { return }
        finished = true
        let client = self.client
        self.client = nil
        await MainActor.run {
            client?.stop()
        }
        continuation.finish()
    }

    private func handleStateChange(_ state: PingState) async {
        switch state {
        case .failed(let error):
            if logging { LoggingService.error("ping failed host=\(self.config.host) error=\(error)", category: .ping) }
            let measurement = PingMeasurement(host: self.config.host,
                                             sequence: 0,
                                             status: .error(error.errorDescription),
                                             timestamp: Date())
            continuation.yield(measurement)
            await finish()
        case .finished:
            if logging { LoggingService.debug("ping finished host=\(self.config.host)", category: .ping) }
            await finish()
        default:
            break
        }
    }

    private func handleEvent(_ event: PingEvent) async {
        switch event.kind {
        case .received(let roundTrip, _, _):
            let millis = roundTrip * 1000.0
            if logging {
                LoggingService.debug("received host=\(self.config.host) seq=\(event.sequence) rtt=\(String(format: "%.2f", millis))ms", category: .ping)
            }
            let measurement = PingMeasurement(host: self.config.host,
                                             sequence: Int(event.sequence),
                                             status: .success(rttMillis: millis),
                                             timestamp: event.timestamp)
            continuation.yield(measurement)
        case .timeout:
            if logging { LoggingService.debug("timeout host=\(self.config.host) seq=\(event.sequence)", category: .ping) }
            let measurement = PingMeasurement(host: self.config.host,
                                             sequence: Int(event.sequence),
                                             status: .timeout,
                                             timestamp: event.timestamp)
            continuation.yield(measurement)
        case .failed(let error):
            if logging { LoggingService.error("error host=\(self.config.host) seq=\(event.sequence) error=\(error)", category: .ping) }
            let measurement = PingMeasurement(host: self.config.host,
                                             sequence: Int(event.sequence),
                                             status: .error(error.errorDescription),
                                             timestamp: event.timestamp)
            continuation.yield(measurement)
            await finish()
        case .sent:
            if logging { LoggingService.debug("sent host=\(self.config.host) seq=\(event.sequence)", category: .ping) }
        }
    }
}
