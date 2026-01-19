// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RemoteGTV",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RemoteGTV",
            targets: ["RemoteGTV"]),
    ],
    targets: [
        .executableTarget(
            name: "RemoteGTV",
            exclude: ["Network/RemoteMote.proto"],
            resources: [
                .process("AppIcon.png")
            ]
        ),
        .testTarget(
            name: "RemoteGTVTests",
            dependencies: ["RemoteGTV"]),
    ]
)
