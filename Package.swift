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
        dependencies: ["XrayKitC", "LibXray"]
    ),
    .target(
        name: "XrayKitC",
        publicHeadersPath: "."
    ),
    .binaryTarget(
        name: "LibXray",
	url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2025.5.17/LibXray.xcframework.zip",
	checksum: "e9a2589b35037387d2fc5a5678be0331d726d6d1c0565a9ceb459a6814582107"
    )
  ]
)
