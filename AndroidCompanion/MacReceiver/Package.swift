// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacReceiver",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacReceiver",
            targets: ["MacReceiver"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacReceiver",
            path: "Sources/MacReceiver"
        )
    ]
)
