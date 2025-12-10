// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EKNetwork",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "EKNetwork",
            targets: ["EKNetwork"]),
    ],
    targets: [
        .target(
            name: "EKNetwork",
            dependencies: []),
        .testTarget(
            name: "EKNetworkTests",
            dependencies: ["EKNetwork"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
