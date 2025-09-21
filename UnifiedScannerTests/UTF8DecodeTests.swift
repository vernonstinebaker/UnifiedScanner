import XCTest
@testable import UnifiedScanner

final class UTF8DecodeTests: XCTestCase {
    func testDecodeCStringValid() {
        let buffer: [CChar] = Array("hello\0".utf8CString)
        let ptr = UnsafePointer<CChar>(buffer)
        let result = decodeCString(ptr, context: "test valid")
        XCTAssertEqual(result, "hello")
    }

    func testDecodeCStringWithNUL() {
        let buffer: [CChar] = Array("hello world\0".utf8CString)
        let ptr = UnsafePointer<CChar>(buffer)
        let result = decodeCString(ptr, context: "test with space")
        XCTAssertEqual(result, "hello world")
    }

    func testDecodeCStringInvalidNoNUL() {
        let buffer: [CChar] = Array("hello".utf8CString.dropLast()) // no \0
        let ptr = UnsafePointer<CChar>(buffer)
        let result = decodeCString(ptr, context: "test no nul")
        XCTAssertNil(result)
    }

    func testDecodeCStringBadUTF8() {
        let invalidUTF8: [CChar] = [CChar(bitPattern: 0xFF), CChar(bitPattern: 0xFE), CChar(bitPattern: 0xFD), CChar(bitPattern: 0x80), 0]
        let ptr = UnsafePointer<CChar>(invalidUTF8)
        let result = decodeCString(ptr, context: "test bad utf8")
        XCTAssertNil(result)
    }

    func testDecodeCStringEmpty() {
        let buffer: [CChar] = [0]
        let ptr = UnsafePointer<CChar>(buffer)
        let result = decodeCString(ptr, context: "test empty")
        XCTAssertEqual(result, "")
    }

    func testDecodeBufferValid() {
        var buffer: [CChar] = Array("test buffer\0".utf8CString)
        let result = decodeBuffer(&buffer, context: "test buffer")
        XCTAssertEqual(result, "test buffer")
    }

    func testDecodeBufferNoNUL() {
        var buffer: [CChar] = Array("no nul".utf8CString.dropLast())
        let result = decodeBuffer(&buffer, context: "test no nul buffer")
        XCTAssertNil(result)
    }

    func testDecodeBufferBadUTF8() {
        var buffer: [CChar] = [CChar(bitPattern: 0xFF), CChar(bitPattern: 0x80), 0]
        let result = decodeBuffer(&buffer, context: "test bad utf8 buffer")
        XCTAssertNil(result)
    }
}
