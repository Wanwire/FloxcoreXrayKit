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
        url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2026.10.22/LibXrayGo.xcframework.zip",
        checksum: "5b2b7dfe94dd816e998ca11ab45df452f5d2997bece2e90aabf1fc64e0776dcb"
    )
  ]
)
