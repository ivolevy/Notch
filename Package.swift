// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "Notch",
            targets: ["DynamicNotch"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DynamicNotch",
            path: "Sources/DynamicNotch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
