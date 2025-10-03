import Foundation
import NetworkExtension
import LibXrayGo

public protocol XrayCoreManagerProtocol {
    func onEmitStatus(code: Int, message: String?)
    func onStart()
    func onStartFailure(message: String?)
    func onStop()
}

public actor XrayCoreManager {
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
        
        func onEmitStatus(_ p0: Int, p1: String?) -> Int {
            onEmitStatusCb?(p0, p1)
            return 0
        }
        
        func onStart() -> Int {
            onStartCb?()
            return 0
        }
        
        func onStartFailure(_ p0: String?) -> Int {
            onStartFailureCb?(p0)
            return 0
        }
        
        func onStop() -> Int {
            onStopCb?()
            return 0
        }
    }
    
    private var xcCallbackHandler: XrayCoreManagerCallbackHandler
    private var callbackHandler: XrayCoreManagerProtocol? = nil
    private var controller: LibxraygoXrayCoreController? = nil
    private var startCompletion: ((NEVPNError?) -> ())? = nil
    
    public init(callbackHandler handler: XrayCoreManagerProtocol? = nil) {
        callbackHandler = handler
        xcCallbackHandler = XrayCoreManagerCallbackHandler()
        controller = LibxraygoNewXrayCoreController(xcCallbackHandler)
    }
      
    private func emittedStatus(code: Int, message: String?) {
        callbackHandler?.onEmitStatus(code: code, message: message)
    }
    
    private func started() {
        startCompletion?(nil)
        callbackHandler?.onStart()
    }
    
    private func startFailed(_ message: String?) {
        let error = NEVPNError(.connectionFailed)
        startCompletion?(error)
        callbackHandler?.onStartFailure(message: message)
    }
    
    private func stopped() {
        callbackHandler?.onStop()
    }
    
    public func start(config: String, assets: URL, completion: @escaping (NEVPNError?) -> ()) {
        xcCallbackHandler.setEmitStatusCallback { [weak self] code, message in
            Task { await self?.emittedStatus(code: code, message: message) }
        }
        xcCallbackHandler.setStartCallback { [weak self] in
            Task { await self?.started() }
        }
        xcCallbackHandler.setStartFailureCallback { [weak self] message in
            Task { await self?.startFailed(message) }
        }
        xcCallbackHandler.setStopCallback { [weak self] in
            Task { await self?.stopped() }
        }

        LibxraygoInitXrayCoreEnv(assets.path)
        
        guard let controller else {
            let error = NEVPNError(.connectionFailed)
            completion(error)
            return
        }

        startCompletion = completion
        controller.start(config)
    }
    
    public func start(config: String, assets: URL) async -> Result<Void, NEVPNError> {
        await withCheckedContinuation { continuation in
            start(config: config, assets: assets) { (error: NEVPNError?) in
                guard let error else { return continuation.resume(returning: .success(())) }
                continuation.resume(returning: .failure(error))
            }
        }
    }
    
    public func stop() {
        controller?.stop()
    }
}

public enum XrayCore {
    public static let controller: XrayCoreManager = XrayCoreManager()
    
    public static func run(config: Data, assets: URL) -> Result<Void, NEVPNError> {
        guard let dataStr = String(data: config, encoding: .utf8) else {
            return .failure(NEVPNError(.configurationReadWriteFailed))
        }

        let group = DispatchGroup()
        var taskResult: Result<Void, NEVPNError> = .failure(NEVPNError(.configurationReadWriteFailed))
        
        group.enter()
        
        Task {
            let result = await controller.start(config: dataStr, assets: assets)
            taskResult = result
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
