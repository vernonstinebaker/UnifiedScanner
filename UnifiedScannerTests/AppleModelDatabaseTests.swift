import XCTest
@testable import UnifiedScanner

final class AppleModelDatabaseTests: XCTestCase {

    func testSharedInstance() {
        let db1 = AppleModelDatabase.shared
        let db2 = AppleModelDatabase.shared
        XCTAssert(db1 === db2, "Shared instance should be the same object")
    }

    func testNameLookup() {
        let db = AppleModelDatabase.shared

        // Test some known Apple model identifiers
        // These should exist in the bundled CSV
        XCTAssertNotNil(db.name(for: "iPhone14,7"), "Should find iPhone 14")
        XCTAssertNotNil(db.name(for: "Mac14,2"), "Should find MacBook Air")

        // Test case insensitivity
        if let name1 = db.name(for: "iPhone14,7"),
           let name2 = db.name(for: "IPHONE14,7") {
            XCTAssertEqual(name1, name2, "Case insensitive lookup should return same result")
        }

        // Test non-existent model
        XCTAssertNil(db.name(for: "NonExistentModel"), "Should return nil for unknown model")
    }

    func testEmptyOrInvalidInput() {
        let db = AppleModelDatabase.shared

        XCTAssertNil(db.name(for: ""), "Empty string should return nil")
        XCTAssertNil(db.name(for: "   "), "Whitespace only should return nil")
    }

    func testDatabaseLoading() {
        let db = AppleModelDatabase.shared

        // Force loading by calling name lookup
        _ = db.name(for: "dummy")

        // Since it's lazy loaded, we can't directly test the count without exposing internals
        // But we can test that it doesn't crash and returns consistent results
        let result1 = db.name(for: "iPhone14,7")
        let result2 = db.name(for: "iPhone14,7")
        XCTAssertEqual(result1, result2, "Results should be consistent across calls")
    }

    func testCSVLineParsing() {
        // This is testing a private method, but we can test it indirectly
        // by ensuring the database loads correctly, which uses the parser

        let db = AppleModelDatabase.shared
        // If parsing works, we should get some results
        let hasSomeData = db.name(for: "iPhone14,7") != nil || db.name(for: "Mac14,2") != nil
        XCTAssertTrue(hasSomeData, "Database should contain some Apple model data")
    }
}