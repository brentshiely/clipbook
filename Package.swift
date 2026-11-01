// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipbook",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClipbookCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Clipbook",
            dependencies: ["ClipbookCore"],
            linkerSettings: [.linkedFramework("AVKit")]     // SwiftUI's VideoPlayer needs it loaded at runtime
        ),
        .testTarget(
            name: "ClipbookCoreTests",
            dependencies: ["ClipbookCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
