import Foundation

/// Reads resident memory for WebContent processes by PID. Uses one `/bin/ps` call for all PIDs
/// (WebKit runs each tab in its own process; `_webProcessIdentifier` gives the PID). `ps` can read
/// any same-user process's RSS without special entitlements — the same approach the S1 diagnostic uses.
enum ProcessMemory {
    /// `[pid: residentMB]` for the given PIDs (empty for any that can't be read).
    static func residentMB(pids: [pid_t]) -> [pid_t: Double] {
        let unique = Array(Set(pids)).filter { $0 > 0 }
        guard !unique.isEmpty else { return [:] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "pid=,rss=", "-p", unique.map(String.init).joined(separator: ",")]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()   // read before wait (avoid deadlock)
        p.waitUntilExit()
        var out: [pid_t: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.count >= 2, let pid = pid_t(cols[0]), let kb = Double(cols[1]) {
                out[pid] = kb / 1024.0
            }
        }
        return out
    }
}
