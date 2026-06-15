// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AWSBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AWSBar",
            targets: ["AWSBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AWSBar"
        )
    ]
)
