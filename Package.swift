// swift-tools-version: 5.10
// SPDX-License-Identifier: GPL-2.0-or-later
import PackageDescription

let package = Package(
    name: "Cynosa",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CynosaKit", targets: ["CynosaKit"]),
        .executable(name: "cynosa", targets: ["cynosa"]),
        .executable(name: "CynosaApp", targets: ["CynosaApp"]),
    ],
    targets: [
        .target(name: "CUSB", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "CynosaKit", dependencies: ["CUSB"], linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "cynosa", dependencies: ["CynosaKit"]),
        .executableTarget(name: "CynosaApp", dependencies: ["CynosaKit"]),
        .executableTarget(name: "render-previews", dependencies: ["CynosaKit"]),
        .testTarget(name: "CynosaKitTests", dependencies: ["CynosaKit"]),
    ]
)
