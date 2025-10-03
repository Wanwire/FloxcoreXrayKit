# XrayKit

[![Release](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml/badge.svg)](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml)
  
[Download](https://github.com/Wanwire/FloxcoreXrayKit/releases/latest "download latest release")

### Usage
```swift
import XrayKit

var controller: XrayCoreManager = XrayCoreManager()

/* Find path to geoip.dat and geosite.dat in Bundle resources */
let geoip = Bundle.main.url(forResource: "geoip", withExtension: "dat")!
let assets = geoip.deletingLastPathComponent()

/* Define your configuration */
let configuration = """
{
    "your": "configuration"
}
"""

/* Start XrayCore */
Task {
    let result = await controller.start(config: configuration, assets: assets)
    switch result {
    case .success:
        print("XrayCore started successfully")
    case .failure(let failure):
        print("XrayCore failed to start: \(failure.localizedDescription)")
    }
}

/* Stop XrayCore */
Task {
    await controller.stop()
}

// DEPRECATED:
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

