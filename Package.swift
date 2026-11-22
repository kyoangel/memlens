// swift-tools-version:6.0
import Foundation
import PackageDescription

// Command Line Tools ship the Swift Testing macro plugin outside the compiler's
// default plugin search path (and no Xcode is installed); point the compiler at
// it when it exists so a plain `swift test` works.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])]
    : []

let package = Package(
    name: "MemLens",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MemLensCore"),
        .executableTarget(name: "MemLensApp", dependencies: ["MemLensCore"]),
        .testTarget(
            name: "MemLensCoreTests",
            dependencies: ["MemLensCore"],
            swiftSettings: testSwiftSettings
        ),
    ]
)
