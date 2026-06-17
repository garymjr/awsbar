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
        ),
        .testTarget(
            name: "AWSBarTests",
            dependencies: ["AWSBar"],
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
