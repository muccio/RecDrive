// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecDrive",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "RecDrive",
            targets: ["RecDrive"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "RecDrive",
            dependencies: [],
            path: "Sources/RecDrive",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Security"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
