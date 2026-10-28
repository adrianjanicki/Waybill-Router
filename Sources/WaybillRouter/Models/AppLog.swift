import Foundation

/// Prosty dziennik zdarzeń aplikacji w pliku (Documents/dziennik.log).
/// Podgląd i eksport: Ustawienia → Dziennik zdarzeń.
enum AppLog {
    private static let maxBytes = 500_000
    private static let queue = DispatchQueue(label: "AppLog")

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dziennik.log")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func log(_ message: String) {
        let line = "\(stamp.string(from: .now))  \(message)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        queue.async {
            let url = fileURL
            let data = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
            trimIfNeeded(url)
        }
    }

    static func read() -> String {
        queue.sync { (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "" }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Gdy plik urośnie, zostawiamy tylko drugą połowę.
    private static func trimIfNeeded(_ url: URL) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        var tail = data.suffix(maxBytes / 2)
        if let nl = tail.firstIndex(of: UInt8(ascii: "\n")) { tail = tail[(nl + 1)...] }
        try? Data(tail).write(to: url)
    }
}
