// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VidPress",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VidPressNative", targets: ["VidPressNative"])
    ],
    targets: [
        .executableTarget(
            name: "VidPressNative",
            path: "Sources/VidPressNative"
        )
    ]
)
