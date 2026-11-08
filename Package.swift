// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Serein",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(
            name: "Serein",
            targets: ["Serein"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Serein",
            path: "Sources/Serein"
        )
    ]
)
