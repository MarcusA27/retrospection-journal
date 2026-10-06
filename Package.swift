// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Retrospection",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Self-contained SQLCipher (SQLite 3.51 + SQLCipher 4.12, LibTomCrypt crypto).
        // Pure SwiftPM, no system SQLite or OpenSSL dependency. Exposes the C API as `import SQLCipher`.
        .package(url: "https://github.com/skiptools/swift-sqlcipher.git", from: "1.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Retrospection",
            dependencies: [
                .product(name: "SQLCipher", package: "swift-sqlcipher")
            ],
            path: "Sources/Retrospection",
            swiftSettings: [
                // The capture path crosses a C event-tap callback and AppKit's main actor with
                // shared mutable state. Swift 5 language mode keeps that pragmatic; the boundaries
                // are guarded explicitly (main-thread hops, a single capture serial queue).
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "RetrospectionTests",
            dependencies: ["Retrospection"],
            path: "Tests/RetrospectionTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
