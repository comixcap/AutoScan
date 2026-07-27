// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoScan",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AutoScan",
            path: "Sources/AutoScan",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
