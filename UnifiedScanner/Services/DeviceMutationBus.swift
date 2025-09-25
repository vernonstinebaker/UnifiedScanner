import Foundation

/// Class responsible for collecting and distributing device mutation events.
/// This decouples discovery providers from the snapshot store, allowing for better
/// testability and separation of concerns.
@MainActor
public final class DeviceMutationBus {
    static let shared = DeviceMutationBus()
    private var continuations: [UUID: AsyncStream<DeviceMutation>.Continuation] = [:]
    private var buffer: [DeviceMutation] = []
    private let bufferSize: Int

    init(bufferSize: Int = 256) {
        self.bufferSize = bufferSize
    }

    /// Emit a mutation event to all listeners
    func emit(_ mutation: DeviceMutation) {
        // Add to buffer for new subscribers
        buffer.append(mutation)
        if buffer.count > bufferSize {
            buffer.removeFirst(buffer.count - bufferSize)
        }

        // Send to all active continuations
        for (_, continuation) in continuations {
            continuation.yield(mutation)
        }
    }

    /// Get a stream of mutations, optionally including buffered events
    func mutationStream(includeBuffered: Bool = true) -> AsyncStream<DeviceMutation> {
        return AsyncStream(bufferingPolicy: .bufferingOldest(bufferSize)) { continuation in
            let id = UUID()
            continuations[id] = continuation

            // Send buffered events to new subscriber if requested
            if includeBuffered {
                for mutation in buffer {
                    continuation.yield(mutation)
                }
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Clear all buffered mutations
    func clearBuffer() {
        buffer.removeAll()
    }
    
    /// Reset all state - for testing only
    func resetForTesting() {
        buffer.removeAll()
        for (_, continuation) in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }

    /// Get current buffer size for debugging
    var bufferedCount: Int {
        buffer.count
    }
}