// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kino",
    platforms: [
        .macOS(.v13)
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
