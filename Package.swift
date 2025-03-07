// swift-tools-version: 5.5
//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2025 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-libp2p-dnsaddr",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LibP2PDNSAddr",
            targets: ["LibP2PDNSAddr"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.

        // LibP2P Core Modules
        .package(url: "https://github.com/swift-libp2p/swift-libp2p.git", .upToNextMinor(from: "0.2.0")),

        // DNS + NIO
        .package(url: "https://github.com/orlandos-nl/DNSClient.git", .upToNextMajor(from: "2.4.4")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LibP2PDNSAddr",
            dependencies: [
                .product(name: "LibP2P", package: "swift-libp2p"),
                .product(name: "DNSClient", package: "DNSClient"),
            ]
        ),
        .testTarget(
            name: "LibP2PDNSAddrTests",
            dependencies: ["LibP2PDNSAddr"]
        ),
    ]
)
