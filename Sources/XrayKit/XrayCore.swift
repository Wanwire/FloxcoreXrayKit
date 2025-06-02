import Foundation
import NetworkExtension
import LibXray
    
public enum XrayCore {
    public static func run(config url: URL, assets: URL) -> Result<Void, NEVPNError> {
        let args: [String] = ["libxray", "-c", url.path]
        var argv = args.map { strdup($0) }
        let argc = Int32(argv.count)
        
        let env: [String] = ["xray.location.asset=\(assets.path)"]
        var envv = env.map { strdup($0) }
        let envc = Int32(envv.count)
        
        let result = libxray_main(argc, &argv, envc, &envv)
        
        for ptr in envv { free(ptr) }
        for ptr in argv { free(ptr) }
        
        guard result == 0 else {
            let error = NEVPNError(.configurationInvalid)
            return .failure(error)
        }
        
        return .success(())
    }

    public static func quit() {
        libxray_stop()
    }
}

