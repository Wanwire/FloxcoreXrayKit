// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "XrayKit",
  platforms: [.iOS(.v16), .macOS(.v14), .macCatalyst(.v16), .tvOS(.v17), .visionOS(.v1)],
  products: [
    .library(
        name: "XrayKit",
        targets: ["XrayKit"]
    )
  ],
  targets: [
    .target(
        name: "XrayKit",
        dependencies: ["XrayKitUtil", "LibXrayGo"]
    ),
    .target(
        name: "XrayKitUtil",
        publicHeadersPath: "include" 
    ),
    .binaryTarget(
        name: "LibXrayGo",
        url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2026.10.21/LibXrayGo.xcframework.zip",
        checksum: "bf82789c145dbe435b61a1116ea1aa554b1f5e81e47e254460d20a46f414a42b"
    )
  ]
)
