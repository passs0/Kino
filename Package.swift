// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Player",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Player",
            targets: ["Player"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Player",
            path: "Sources/Player"
        )
    ],
    swiftLanguageModes: [.v5]
)
