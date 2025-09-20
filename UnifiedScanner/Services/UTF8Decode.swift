import Foundation

/// Decodes a C char buffer (assumed NUL-terminated) into a Swift String, logging when invalid.
/// Returns nil if decoding fails (callers can choose a fallback or skip the value).
@inline(__always)
func decodeCString(_ buffer: UnsafePointer<CChar>, context: @autoclosure @Sendable () -> String) -> String? {
    if let s = String(validatingCString: buffer) { return s }
    let ctx = context()
    LoggingService.warn("utf8 decode failed context=\(ctx)")
    return nil
}

/// Decodes a mutable C char array passed by reference (e.g. &array) into a String.
@inline(__always)
func decodeBuffer(_ buffer: inout [CChar], context: @autoclosure @Sendable () -> String) -> String? {
    return buffer.withUnsafeBufferPointer { ptr in
        guard let base = ptr.baseAddress else { return nil }
        return decodeCString(base, context: context())
    }
}
