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
        dependencies: ["LibXrayGo"]
    ),
    .binaryTarget(
        name: "LibXrayGo",
        url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2025.7.26/LibXrayGo.xcframework.zip",
        checksum: "afaa39297c8ad1585dc0b321a163045589aeda0c4a4ac6605843248b407e8b44"
    )
  ]
)
