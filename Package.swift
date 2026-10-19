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
        url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2026.10.17/LibXrayGo.xcframework.zip",
        checksum: "8c43286adf9a559cb0df7dfaf9b7eb1500422e4330606c71c78c6b5ca68cbb4d"
    )
  ]
)
