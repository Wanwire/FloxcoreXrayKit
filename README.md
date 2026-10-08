# XrayKit

[![Release](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml/badge.svg)](https://github.com/Wanwire/FloxcoreXrayKit/actions/workflows/release.yml)
  
[Download](https://github.com/Wanwire/FloxcoreXrayKit/releases/latest "download latest release")

### xray-core patches
The build uses xray-core with the patches in `patches/xray-core`. `make xray-core`
copies the xray-core version that `go.mod` requires to `.tmp/xray-core` and applies
the patches; `go.mod` replaces xray-core with that directory. `make` and the release
workflow do this step first. After you change the xray-core version in `go.mod`,
make sure that the patches still apply.

- `dns-log.patch`: when the log config sets `dnsLog`, the DNS log shows each DNS
  query that passes through the dispatcher, with its ID, tries, result code and time
  to reply, or that no reply came. Without `dnsLog`, xray-core works as without the patch.

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

/* Query the data transferred over the outbounds */
let traffic = controller.queryOutboundTraffic()
print("Sent: \(traffic.totalSent) bytes, received: \(traffic.totalReceived) bytes")

/* Inspect the transferred data per outbound tag */
for outbound in traffic {
    print("\(outbound.tag): sent \(outbound.sent), received \(outbound.received)")
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

