// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kino",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "Kino",
            targets: ["Kino"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Kino",
            path: "Sources/Kino"
        )
    ]
)
