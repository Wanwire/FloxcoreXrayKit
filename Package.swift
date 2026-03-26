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
        url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2026.3.23/LibXrayGo.xcframework.zip",
        checksum: "755ab81eca9c1709d42d9a2b0d3c5f89b8d268bdb1ae7862954237837d1ea665"
    )
  ]
)
