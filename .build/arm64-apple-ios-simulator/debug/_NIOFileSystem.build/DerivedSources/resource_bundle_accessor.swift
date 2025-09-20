import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("swift-nio__NIOFileSystem.bundle").path
        let buildPath = "/Volumes/X9Pro/Local/Programming/Swift/netscan/UnifiedScanner/.build/arm64-apple-ios-simulator/debug/swift-nio__NIOFileSystem.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}