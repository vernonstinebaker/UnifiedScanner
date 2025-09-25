import Combine
import Foundation
import SwiftUI

@MainActor
protocol DeviceMutationBusProviding {
    func emit(_ mutation: DeviceMutation)
    func mutationStream(includeBuffered: Bool) -> AsyncStream<DeviceMutation>
    func clearBuffer()
    var bufferedCount: Int { get }
}

@MainActor
struct DeviceMutationBusAdapter: DeviceMutationBusProviding {
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

    var bufferedCount: Int {
        bus.bufferedCount
    }

    var concreteBus: DeviceMutationBus { bus }
}

protocol LoggingServiceProviding {
    func setMinimumLevel(_ level: LoggingService.Level)
    func setEnabledCategories(_ categories: Set<LoggingService.Category>)
    func debug(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category)
    func info(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category)
    func warn(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category)
    func error(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category)
}

struct LoggingServiceAdapter: LoggingServiceProviding {
    func setMinimumLevel(_ level: LoggingService.Level) {
        LoggingService.setMinimumLevel(level)
    }

    func setEnabledCategories(_ categories: Set<LoggingService.Category>) {
        LoggingService.setEnabledCategories(categories)
    }

    func debug(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category) {
        LoggingService.debug(message(), category: category)
    }

    func info(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category) {
        LoggingService.info(message(), category: category)
    }

    func warn(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category) {
        LoggingService.warn(message(), category: category)
    }

    func error(_ message: @autoclosure @escaping @Sendable () -> String, category: LoggingService.Category) {
        LoggingService.error(message(), category: category)
    }
}

protocol ClassificationServiceProviding {
    func classify(device: Device) async -> Device.Classification
    func setOUILookupProvider(_ provider: OUILookupProviding?)
}

struct ClassificationServiceAdapter: ClassificationServiceProviding {
    func classify(device: Device) async -> Device.Classification {
        await ClassificationService.classify(device: device)
    }

    func setOUILookupProvider(_ provider: OUILookupProviding?) {
        ClassificationService.setOUILookupProvider(provider)
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let deviceMutationBus: DeviceMutationBus
    let deviceMutationBusProvider: DeviceMutationBusProviding
    let loggingService: LoggingServiceProviding
    let classificationService: ClassificationServiceProviding

    init(deviceMutationBus: DeviceMutationBus = .shared,
         loggingService: LoggingServiceProviding = LoggingServiceAdapter(),
         classificationService: ClassificationServiceProviding = ClassificationServiceAdapter()) {
        self.deviceMutationBus = deviceMutationBus
        self.deviceMutationBusProvider = DeviceMutationBusAdapter(bus: deviceMutationBus)
        self.loggingService = loggingService
        self.classificationService = classificationService
    }

    func makePortScanService() -> PortScanService {
        PortScanService(mutationBus: deviceMutationBus)
    }

    func makeHTTPFingerprintService() -> HTTPFingerprintService {
        HTTPFingerprintService(mutationBus: deviceMutationBus)
    }

    func makeSnapshotService(persistenceKey: String = "unifiedscanner:devices:v1",
                             persistence: DevicePersistence? = nil) -> SnapshotService {
        SnapshotService(persistenceKey: persistenceKey,
                        persistence: persistence,
                        classification: ClassificationService.self,
                        mutationBus: deviceMutationBus)
    }
}
