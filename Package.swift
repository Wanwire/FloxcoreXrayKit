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
        url: "https://github.com/Wanwire/FloxcoreXrayKit/releases/download/2026.8.29/LibXrayGo.xcframework.zip",
        checksum: "2e51edb289a2197b40fc8428e03de92699416e678ca2a1876f710474ab2e0eec"
    )
  ]
)
