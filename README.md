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
- `liveness-demote.patch`: with `demote` in the settings of a `leastLoad` balancer, e.g.
  `{"failures": 3, "window": "20s", "replyTimeout": "5s", "minReplyBytes": 1}`, the
  balancer passes over an outbound whose last connections within the window got no
  reply, and none of whose connections got one lately, until its next health check
  result, and spreads its picks over servers. The patch also keeps the results of the
  pings that are under way when the next round of health checks cancels its round.
- `liveness-reset.patch`: `liveness.Reset` forgets what the liveness tracking found.
  `Start` calls it before it creates the new instance, so that nothing carries over
  from the last instance.
- `refresh-connections.patch`: adds `splithttp.ForgetConnections` and
  `burst.Observer.CheckSubjects`, which `refreshConnections()` uses.

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

/* After the device slept, forget stale connections and check the outbounds again */
Task.detached {
    print(controller.refreshConnections())
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

