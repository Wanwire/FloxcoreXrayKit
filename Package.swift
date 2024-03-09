// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "XrayKit",
  platforms: [.iOS(.v16), .macOS(.v14), .macCatalyst(.v16), .tvOS(.v17)],
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
	url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/1.8.8/LibXray.xcframework.zip",
	checksum: "b68b8dd17cd541a249db1a45df1d00d87c7729fbcbe868d21a5b5bd0281d77c3"
    )
  ]
)
