# XrayKit

[![Release](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml/badge.svg)](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml)
  
[Download](https://github.com/Wanwire/FloxcoreXrayKit/releases/latest "download latest release")

### Usage
```swift
import XrayKit

/* Find path to geoip.dat and geosite.dat in Bundle resources */
let geoip = Bundle.main.url(forResource: "geoip", withExtension: "dat")!
let assets = geoip.deletingLastPathComponent()

/* Define your configuration */
let configurationData = """
{
  "your": "configuration"
}
""".data(using: .utf8)

/* Start XrayCore */
XRayCore.run(configuration: configurationData, assets: assets) { error in
    if let error = error {
        // Present error
    }
}

/* Stop XrayCore */
XRayCore.quit()

```

