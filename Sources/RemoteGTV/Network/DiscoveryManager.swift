import Foundation
import Network
import Combine

class DiscoveryManager: ObservableObject {
    @Published var discoveredDevices: [NWBrowser.Result] = []
    
    private var browser: NWBrowser?
    
    func startDiscovery() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_androidtvremote2._tcp", domain: "local.")
        let parameters = NWParameters.tcp
        
        browser = NWBrowser(for: descriptor, using: parameters)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredDevices = Array(results)
                Logger.shared.log("Discovered \(results.count) devices", category: "Discovery")
            }
        }
        browser?.start(queue: .main)
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }
}
