# XrayKit

[![Release](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml/badge.svg)](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml)
  
[Download](https://github.com/Wanwire/FloxcoreXrayKit/releases/latest "download latest release")

### Usage
```swift
import XrayKit

/* Start XrayCore */
let configurationFile = FileManager.default.temporaryDirectory.appendingPathComponent("xray").appendingPathExtension("json")
// Write Xray configuration to configurationFile

let geoip = Bundle.main.url(forResource: "geoip", withExtension: "dat")!
let assets = geoip.deletingLastPathComponent()

XRayCore.run(configuration: configuratonFile, assets: assets) { error in
    if let error = error {
        // Present error
    }
}

/* Stop XrayCore */
XRayCore.quit()

```

