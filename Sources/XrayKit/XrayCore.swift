import Foundation
import Darwin
import NetworkExtension
import XrayKitUtil
import LibXrayGo

public enum XrayCoreStartError: Error {
    case invalidConfiguration(String)
    case connectionFailed(String)
}

public protocol XrayCoreManagerProtocol {
    func onEmitStatus(code: Int, message: String?)
    func onStart()
    func onStartFailure(message: String?)
    func onStop()
}

/// Cumulative traffic transferred over a single outbound connection since the
/// core was started.
public struct OutboundTraffic {
    /// The outbound tag this traffic is accounted to.
    public let tag: String
    /// Bytes sent (uplink) over this outbound.
    public let sent: Int64
    /// Bytes received (downlink) over this outbound.
    public let received: Int64
}

public extension Array where Element == OutboundTraffic {
    /// Total bytes sent (uplink) across all outbounds.
    var totalSent: Int64 { reduce(0) { $0 + $1.sent } }
    /// Total bytes received (downlink) across all outbounds.
    var totalReceived: Int64 { reduce(0) { $0 + $1.received } }
}

public class XrayCoreManager {
    private class XrayCoreManagerCallbackHandler: NSObject, LibxraygoXrayCoreCallbackHandlerProtocol {
        var onEmitStatusCb: ((Int, String?) -> ())? = nil
        var onStartCb: (() -> ())? = nil
        var onStartFailureCb: ((String?) -> ())? = nil
        var onStopCb: (() -> ())? = nil
        
        func setEmitStatusCallback(_ cb: @escaping (Int, String?) -> Void) {
            self.onEmitStatusCb = cb
        }
        
        func setStartCallback(_ cb: @escaping () -> Void) {
            self.onStartCb = cb
        }
        
        func setStartFailureCallback(_ cb: @escaping (String?) -> Void) {
            self.onStartFailureCb = cb
        }
        
        func setStopCallback(_ cb: @escaping () -> Void) {
            self.onStopCb = cb
        }
        
        public func onEmitStatus(_ p0: Int, p1: String?) -> Int {
            onEmitStatusCb?(p0, p1)
            return 0
        }
        
        public func onStart() -> Int {
            onStartCb?()
            return 0
        }
        
        public func onStartFailure(_ p0: String?) -> Int {
            onStartFailureCb?(p0)
            return 0
        }
        
        public func onStop() -> Int {
            onStopCb?()
            return 0
        }
    }
    private let libXcCallbackHandler: XrayCoreManagerCallbackHandler = .init()
    private var callbackHandler: XrayCoreManagerProtocol? = nil
    private var controller: LibxraygoXrayCoreController? = nil
    private var startCompletion: ((XrayCoreStartError?) -> ())? = nil
    
    public init(callbackHandler handler: XrayCoreManagerProtocol? = nil) {
        callbackHandler = handler
        controller = LibxraygoNewXrayCoreController(libXcCallbackHandler)
    }

    private var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()
        withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0...1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    ret = getpeername(fd, $0, &len)
                }
            }
            if ret != 0 || addr.sc_family != AF_SYSTEM {
                continue
            }
            if ctlInfo.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
                if ret != 0 {
                    continue
                }
            }
            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
    }
      
    private func emittedStatus(code: Int, message: String?) {
        callbackHandler?.onEmitStatus(code: code, message: message)
    }
    
    private func started() {
        startCompletion?(nil)
        startCompletion = nil
        callbackHandler?.onStart()
    }

    private func startFailed(_ message: String?) {
        if let message = message, message.starts(with: "config error") {
            let error = XrayCoreStartError.invalidConfiguration(message)
            startCompletion?(error)
            startCompletion = nil
            callbackHandler?.onStartFailure(message: message)
            return
        }

        let error = XrayCoreStartError.connectionFailed(message ?? "")
        startCompletion?(error)
        startCompletion = nil
        callbackHandler?.onStartFailure(message: message)
    }
    
    private func stopped() {
        callbackHandler?.onStop()
    }
    
    public func start(config: String, assets: URL, withTun: Bool = false, completion: @escaping (XrayCoreStartError?) -> ()) {
        guard
            let tunFd = withTun ? self.tunnelFileDescriptor : 0
        else {
            let error = XrayCoreStartError.connectionFailed("No tun device found")
            completion(error)
            return
        }

        libXcCallbackHandler.setEmitStatusCallback { [weak self] code, message in
            Task { await self?.emittedStatus(code: code, message: message) }
        }
        libXcCallbackHandler.setStartCallback { [weak self] in
            Task { await self?.started() }
        }
        libXcCallbackHandler.setStartFailureCallback { [weak self] message in
            Task { await self?.startFailed(message) }
        }
        libXcCallbackHandler.setStopCallback { [weak self] in
            Task { await self?.stopped() }
        }

        LibxraygoInitXrayCoreAssetEnv(assets.path)
        LibxraygoInitXrayCoreTunFdEnv(tunFd)
        
        guard let controller else {
            let error = XrayCoreStartError.connectionFailed("No controller")
            completion(error)
            return
        }

        // A new start supersedes a pending one; complete the pending start so
        // its waiting task does not stay suspended forever
        if let pendingCompletion = startCompletion {
            startCompletion = nil
            pendingCompletion(.connectionFailed("superseded by a new start"))
        }

        startCompletion = completion
        controller.start(config)
    }
    
    public func start(config: String, assets: URL, withTun: Bool = false) async -> Result<Void, XrayCoreStartError> {
        await withCheckedContinuation { continuation in
            start(config: config, assets: assets, withTun: withTun) { (error: XrayCoreStartError?) in
                guard let error else { return continuation.resume(returning: .success(())) }
                continuation.resume(returning: .failure(error))
            }
        }
    }
    
    public func stop() {
        controller?.stop()
    }

    /// Returns the cumulative traffic transferred over each outbound connection
    /// since the core was started, one entry per outbound tag.
    ///
    /// Values are read without resetting the underlying counters. Use
    /// `totalSent` / `totalReceived` on the result for grand totals. Returns an
    /// empty array when the core is not running or no traffic has been recorded.
    public func queryOutboundTraffic() -> [OutboundTraffic] {
        guard let raw = controller?.queryOutboundTraffic(), !raw.isEmpty else {
            return []
        }

        // The Go layer serializes traffic as ";"-terminated "tag,direction,bytes"
        // records, emitting an "up" and a "down" record for every outbound tag.
        var byTag: [String: (sent: Int64, received: Int64)] = [:]
        var order: [String] = []
        for record in raw.split(separator: ";") {
            let fields = record.split(separator: ",")
            guard fields.count == 3, let bytes = Int64(fields[2]) else { continue }
            let tag = String(fields[0])
            if byTag[tag] == nil {
                byTag[tag] = (0, 0)
                order.append(tag)
            }
            switch String(fields[1]) {
            case "up": byTag[tag]?.sent = bytes
            case "down": byTag[tag]?.received = bytes
            default: break
            }
        }

        return order.map { tag in
            OutboundTraffic(tag: tag, sent: byTag[tag]?.sent ?? 0, received: byTag[tag]?.received ?? 0)
        }
    }
}

/// A snapshot of the Go runtime memory counters inside the Xray core. All sizes
/// are in bytes.
public struct GoMemoryStats {
    /// Bytes in in-use heap spans.
    public let heapInUse: UInt64
    /// Bytes of allocated, still reachable heap objects.
    public let heapAllocated: UInt64
    /// Bytes returned to the operating system. The gap between a shrinking heap
    /// and a shrinking process footprint shows up here.
    public let heapReleased: UInt64
    /// Bytes of heap memory obtained from the operating system.
    public let heapSystem: UInt64
    /// Bytes of stack memory obtained from the operating system.
    public let stackSystem: UInt64
    /// Total bytes obtained from the operating system.
    public let system: UInt64
    /// Number of live goroutines, a direct proxy for live connections.
    public let goroutines: Int

    /// Parses the ","-separated "key=value" form produced by the Go layer.
    fileprivate init?(serialized: String) {
        var values: [String: UInt64] = [:]
        for field in serialized.split(separator: ",") {
            let parts = field.split(separator: "=")
            guard parts.count == 2, let value = UInt64(parts[1]) else { continue }
            values[String(parts[0])] = value
        }
        guard
            let heapInUse = values["heapinuse"],
            let heapAllocated = values["heapalloc"],
            let heapReleased = values["heapreleased"],
            let heapSystem = values["heapsys"],
            let stackSystem = values["stacksys"],
            let system = values["sys"],
            let goroutines = values["goroutines"]
        else {
            return nil
        }
        self.heapInUse = heapInUse
        self.heapAllocated = heapAllocated
        self.heapReleased = heapReleased
        self.heapSystem = heapSystem
        self.stackSystem = stackSystem
        self.system = system
        self.goroutines = Int(goroutines)
    }
}

public enum XrayCore {
    public static let controller: XrayCoreManager = XrayCoreManager()

    /// Reads the Go runtime memory counters. Returns nil when the values cannot
    /// be parsed.
    public static func memoryStats() -> GoMemoryStats? {
        GoMemoryStats(serialized: LibxraygoGoMemoryStats())
    }

    /// Runs a garbage collection and returns as much unused memory to the
    /// operating system as the Go runtime can. Blocks until it completes.
    public static func freeOSMemory() {
        LibxraygoGoFreeOSMemory()
    }

    /// The allocation sites holding the most live heap memory, largest first,
    /// one per line. Runs a garbage collection first, so it is not cheap — call
    /// it when diagnosing retention, not on a timer.
    public static func heapProfile(top: Int = 12) -> String {
        LibxraygoGoHeapProfile(top)
    }
    
    public static func run(config: Data, assets: URL) -> Result<Void, NEVPNError> {
        guard let dataStr = String(data: config, encoding: .utf8) else {
            return .failure(NEVPNError(.configurationReadWriteFailed))
        }

        let group = DispatchGroup()
        var taskResult: Result<Void, NEVPNError> = .failure(NEVPNError(.configurationReadWriteFailed))
        
        group.enter()
        
        Task {
            let result = await controller.start(config: dataStr, assets: assets)
            switch result {
            case .failure(let error):
                switch error {
                case .connectionFailed:
                    taskResult = .failure(NEVPNError(.connectionFailed))
                case .invalidConfiguration:
                    taskResult = .failure(NEVPNError(.configurationInvalid))
                }
            case .success:
                taskResult = .success(())
            }
            group.leave()
        }
        
        group.wait()
        
        return taskResult
    }

    public static func quit() {
        Task {
            await controller.stop()
        }
    }
}
