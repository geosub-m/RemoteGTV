import Foundation
import os.log

class Logger: ObservableObject {
    static let shared = Logger()
    
    @Published var logs: [LogEntry] = []
    private let queue = DispatchQueue(label: "com.remotegtv.logger", qos: .utility)
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
        let type: OSLogType
    }
    
    // System log
    private let systemLog = OSLog(subsystem: "com.geosub.RemoteGTV", category: "Network")
    
    func log(_ message: String, category: String = "General", type: OSLogType = .default) {
        // 1. Log to System Console (Unified Logging)
        os_log("%{public}@", log: systemLog, type: type, "[\(category)] \(message)")
        
        // 2. Keep in memory for UI/Export
        queue.async {
            let entry = LogEntry(date: Date(), category: category, message: message, type: type)
            DispatchQueue.main.async {
                self.logs.append(entry)
                // Limit buffer to last 1000 logs
                if self.logs.count > 1000 {
                    self.logs.removeFirst()
                }
            }
        }
        
        // 3. Print to Xcode Console (debug)
        print("[\(category)] \(message)")
    }
    
    func exportLogs() -> String {
        return logs.map { entry in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let time = formatter.string(from: entry.date)
            return "[\(time)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
    
    func clear() {
        queue.async {
            DispatchQueue.main.async {
                self.logs.removeAll()
            }
        }
    }
}
