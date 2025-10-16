import Foundation
import NetworkExtension
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
      
    private func emittedStatus(code: Int, message: String?) {
        callbackHandler?.onEmitStatus(code: code, message: message)
    }
    
    private func started() {
        startCompletion?(nil)
        callbackHandler?.onStart()
    }
    
    private func startFailed(_ message: String?) {
        if let message = message, message.starts(with: "config error") {
            let error = XrayCoreStartError.invalidConfiguration(message)
            startCompletion?(error)
            callbackHandler?.onStartFailure(message: message)
            return
        }

        let error = XrayCoreStartError.connectionFailed(message ?? "")
        startCompletion?(error)
        callbackHandler?.onStartFailure(message: message)
    }
    
    private func stopped() {
        callbackHandler?.onStop()
    }
    
    public func start(config: String, assets: URL, completion: @escaping (XrayCoreStartError?) -> ()) {
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

        LibxraygoInitXrayCoreEnv(assets.path)
        
        guard let controller else {
            let error = XrayCoreStartError.connectionFailed("No controller")
            completion(error)
            return
        }

        startCompletion = completion
        controller.start(config)
    }
    
    public func start(config: String, assets: URL) async -> Result<Void, XrayCoreStartError> {
        await withCheckedContinuation { continuation in
            start(config: config, assets: assets) { (error: XrayCoreStartError?) in
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
