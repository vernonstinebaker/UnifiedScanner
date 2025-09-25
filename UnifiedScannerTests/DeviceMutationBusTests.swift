import XCTest
@testable import UnifiedScanner

@MainActor
final class DeviceMutationBusTests: XCTestCase {

    func testEmitSendsMutationToStream() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        var receivedMutations: [DeviceMutation] = []
        let stream = bus.mutationStream(includeBuffered: false)

        let collectTask = Task {
            for await mutation in stream.prefix(1) {
                receivedMutations.append(mutation)
            }
        }

        let device = Device(primaryIP: "192.168.1.100", ips: ["192.168.1.100"], discoverySources: [.ping])
        let change = DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .ping)
        bus.emit(.change(change))

        _ = await collectTask.value

        XCTAssertEqual(receivedMutations.count, 1)
        guard case .change(let receivedChange) = receivedMutations[0] else {
            XCTFail("Expected change mutation")
            return
        }
        XCTAssertEqual(receivedChange.after.primaryIP, "192.168.1.100")
    }

    func testMutationStreamIncludesBufferedEventsWhenRequested() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let device = Device(primaryIP: "192.168.1.100", ips: ["192.168.1.100"], discoverySources: [.ping])
        let change = DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .ping)
        bus.emit(.change(change))

        var receivedMutations: [DeviceMutation] = []
        let stream = bus.mutationStream(includeBuffered: true)

        let collectTask = Task {
            for await mutation in stream.prefix(1) {
                receivedMutations.append(mutation)
            }
        }

        _ = await collectTask.value

        XCTAssertEqual(receivedMutations.count, 1)
        guard case .change(let receivedChange) = receivedMutations[0] else {
            XCTFail("Expected change mutation")
            return
        }
        XCTAssertEqual(receivedChange.after.primaryIP, "192.168.1.100")
    }

    func testMutationStreamExcludesBufferedEventsWhenNotRequested() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let device = Device(primaryIP: "192.168.1.100", ips: ["192.168.1.100"], discoverySources: [.ping])
        let change = DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .ping)
        bus.emit(.change(change))

        var receivedMutations: [DeviceMutation] = []
        _ = bus.mutationStream(includeBuffered: false)

        let collectTask = Task {
            // Wait a bit to ensure no buffered events are sent
            try? await Task.sleep(nanoseconds: 100_000_000)
            receivedMutations = []
        }

        _ = await collectTask.value

        XCTAssertTrue(receivedMutations.isEmpty, "Should not receive buffered events when includeBuffered is false")
    }

    func testMultipleSubscribersReceiveMutations() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        var received1: [DeviceMutation] = []
        var received2: [DeviceMutation] = []

        let stream1 = bus.mutationStream(includeBuffered: false)
        let stream2 = bus.mutationStream(includeBuffered: false)

        let task1 = Task {
            for await mutation in stream1.prefix(1) {
                received1.append(mutation)
            }
        }

        let task2 = Task {
            for await mutation in stream2.prefix(1) {
                received2.append(mutation)
            }
        }

        let device = Device(primaryIP: "192.168.1.100", ips: ["192.168.1.100"], discoverySources: [.ping])
        let change = DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .ping)
        bus.emit(.change(change))

        _ = await task1.value
        _ = await task2.value

        XCTAssertEqual(received1.count, 1)
        XCTAssertEqual(received2.count, 1)
        guard case .change(let change1) = received1[0], case .change(let change2) = received2[0] else {
            XCTFail("Expected change mutations")
            return
        }
        XCTAssertEqual(change1.after.primaryIP, "192.168.1.100")
        XCTAssertEqual(change2.after.primaryIP, "192.168.1.100")
    }

    func testBufferSizeLimit() async {
        let bus = DeviceMutationBus(bufferSize: 2)
        defer { bus.resetForTesting() }

        // Emit more than buffer size
        for i in 1...3 {
            let device = Device(primaryIP: "192.168.1.\(i)", ips: ["192.168.1.\(i)"], discoverySources: [.ping])
            let change = DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .ping)
            bus.emit(.change(change))
        }

        XCTAssertEqual(bus.bufferedCount, 2, "Buffer should be limited to 2")

        var receivedMutations: [DeviceMutation] = []
        let stream = bus.mutationStream(includeBuffered: true)

        let collectTask = Task {
            for await mutation in stream.prefix(2) {
                receivedMutations.append(mutation)
            }
        }

        _ = await collectTask.value

        XCTAssertEqual(receivedMutations.count, 2)
        // Should receive the last 2 mutations
        guard case .change(let change1) = receivedMutations[0], case .change(let change2) = receivedMutations[1] else {
            XCTFail("Expected change mutations")
            return
        }
        XCTAssertEqual(change1.after.primaryIP, "192.168.1.2")
        XCTAssertEqual(change2.after.primaryIP, "192.168.1.3")
    }

    func testClearBuffer() async {
        let bus = DeviceMutationBus()
        defer { bus.resetForTesting() }

        let device = Device(primaryIP: "192.168.1.100", ips: ["192.168.1.100"], discoverySources: [.ping])
        let change = DeviceChange(before: nil, after: device, changed: Set(DeviceField.allCases), source: .ping)
        bus.emit(.change(change))

        XCTAssertEqual(bus.bufferedCount, 1)

        bus.clearBuffer()

        XCTAssertEqual(bus.bufferedCount, 0)

        var receivedMutations: [DeviceMutation] = []
        _ = bus.mutationStream(includeBuffered: true)

        let collectTask = Task {
            // Wait a bit to ensure no events
            try? await Task.sleep(nanoseconds: 100_000_000)
            receivedMutations = []
        }

        _ = await collectTask.value

        XCTAssertTrue(receivedMutations.isEmpty, "Should not receive any buffered events after clear")
    }

    func testSharedInstance() {
        let bus1 = DeviceMutationBus.shared
        let bus2 = DeviceMutationBus.shared
        XCTAssert(bus1 === bus2, "Shared instance should be the same object")
    }
}