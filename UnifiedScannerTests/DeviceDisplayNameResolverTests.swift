import XCTest
@testable import UnifiedScanner

final class DeviceDisplayNameResolverTests: XCTestCase {
    func testUserOverrideWins() {
        let d = Device(primaryIP: "192.168.1.10", hostname: "macmini.local", vendor: "Apple", modelHint: "macmini9,1", name: "Basement Mac")
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Basement Mac")
        XCTAssertEqual(resolved?.score, 100)
    }

    func testModelBeatsHostname() {
        var d = Device(primaryIP: "192.168.1.20", hostname: "macmini.local", vendor: "Apple", modelHint: "macmini9,1")
        d.classification = Device.Classification(formFactor: .computer, rawType: "mac_mini", confidence: .high, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Mac mini")
    }

    func testClassificationFallback() {
        var d = Device(primaryIP: "192.168.1.30", hostname: "unknown-device", vendor: nil, modelHint: nil)
        d.classification = Device.Classification(formFactor: .router, rawType: "tplink_router", confidence: .high, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Tplink Router")
    }

    func testHostnameWhenMeaningful() {
        let d = Device(primaryIP: "192.168.1.40", hostname: "livingroom-tv", vendor: nil, modelHint: nil)
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Livingroom Tv")
    }

    func testVendorOnlyFallback() {
        let d = Device(primaryIP: "192.168.1.50", hostname: nil, vendor: "Xiaomi", modelHint: nil)
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Xiaomi")
    }

    func testNumericHostnameSuppressed() {
        let d = Device(primaryIP: "192.168.1.60", hostname: "0-1-2", vendor: "Apple", modelHint: nil)
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Apple")
    }

    func testHomePodBrandCasing() {
        var d = Device(primaryIP: "192.168.1.70", hostname: nil, vendor: "Apple", modelHint: nil)
        // Use speaker formFactor, rawType still drives name
        d.classification = Device.Classification(formFactor: .speaker, rawType: "homepod", confidence: .high, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "HomePod")
    }

    func testIPadBrandCasing() {
        var d = Device(primaryIP: "192.168.1.71", hostname: nil, vendor: "Apple", modelHint: nil)
        d.classification = Device.Classification(formFactor: .tablet, rawType: "ipad", confidence: .high, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "iPad")
    }

    func testIPhoneBrandCasing() {
        var d = Device(primaryIP: "192.168.1.72", hostname: nil, vendor: "Apple", modelHint: nil)
        d.classification = Device.Classification(formFactor: .phone, rawType: "iphone", confidence: .high, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "iPhone")
    }

    func testAppleTVBrandCasing() {
        var d = Device(primaryIP: "192.168.1.80", hostname: nil, vendor: "Apple", modelHint: nil)
        d.classification = Device.Classification(formFactor: .tv, rawType: "apple_tv", confidence: .high, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "Apple TV")
    }

    func testAppleModelIdentifierHomePodMini() {
        let d = Device(primaryIP: "192.168.1.104", hostname: nil, vendor: "Apple", modelHint: "AudioAccessory5,1")
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "HomePod")
    }

    func testAppleModelInferenceFromHostname() {
        let d = Device(primaryIP: "192.168.1.90", hostname: "johns-macbook-pro", vendor: "Apple", modelHint: nil)
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "MacBook Pro")
    }

    func testHomePodInferenceFromHostname() {
        let d = Device(primaryIP: "192.168.1.91", hostname: "kitchen-homepod", vendor: "Apple", modelHint: nil)
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "HomePod")
    }

    func testNumericIDFilteredWhenBetterCandidateExists() {
        var d = Device(primaryIP: nil, hostname: "macbookair", vendor: "Apple", modelHint: nil)
        d.classification = Device.Classification(formFactor: .laptop, rawType: nil, confidence: .medium, reason: "mock", sources: [])
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertNotEqual(resolved?.value, d.id) // should prefer model inference
        XCTAssertEqual(resolved?.value, "MacBook Air")
    }

    func testAppleModelIdentifierMacBookAir() {
        let d = Device(primaryIP: "192.168.1.100", hostname: nil, vendor: "Apple", modelHint: "Mac14,2")
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "MacBook Air")
    }

    func testAppleModelIdentifierMacBookPro() {
        let d = Device(primaryIP: "192.168.1.101", hostname: nil, vendor: "Apple", modelHint: "MacBookPro18,3")
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "MacBook Pro")
    }

    func testAppleModelIdentifieriPhone14() {
        let d = Device(primaryIP: "192.168.1.102", hostname: nil, vendor: "Apple", modelHint: "iPhone14,7")
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "iPhone")
    }

    func testAppleModelIdentifierHomePod() {
        let d = Device(primaryIP: "192.168.1.103", hostname: nil, vendor: "Apple", modelHint: "AudioAccessory6,1")
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "HomePod")
    }

    func testFingerprintModelOverridesIncorrectModelHint() {
        let d = Device(primaryIP: "192.168.1.120", hostname: nil, vendor: "Apple", modelHint: "UnknownXYZ1,1", fingerprints: ["model": "MacBookPro18,3"]) // incorrect legacy hint, correct fingerprint model
        let resolved = DeviceDisplayNameResolver.resolve(for: d)
        XCTAssertEqual(resolved?.value, "MacBook Pro")
    }


}
