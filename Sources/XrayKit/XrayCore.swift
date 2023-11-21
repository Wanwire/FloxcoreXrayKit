import Foundation
import NetworkExtension
import LibXray
    
public enum XrayCore {
    private static var running_on_pid: pid_t = 0

    public static func run(config url: URL, assets: URL, _ completion: @escaping (NEVPNError?) -> ()) {
        let t = Task(priority: .high) {
            running_on_pid = getpid()
            guard running_on_pid > 0 else {
                print("XrayCore cannot be running on pid \(running_on_pid). Bailing out.")
                let error = NEVPNError(.configurationInvalid)
                completion(error)
                return
            }
                
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
                completion(error)
                return
            }
                
            completion(nil)
        }
    }

    public static func quit() {
        kill(running_on_pid, SIGUSR1)
    }
}

