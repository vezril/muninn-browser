import Foundation

/// Downloads the video on the current page by shelling out to **yt-dlp** (+ **ffmpeg** to mux/convert) —
/// the only realistic way to handle YouTube/Facebook/Instagram/… adaptive streams + rotating ciphers.
/// Requires yt-dlp & ffmpeg on the machine (Homebrew). Parses `--newline` progress and reports the final
/// file via `--print after_move:filepath`. All state is serialized on `io`; callbacks fire on the main queue.
final class VideoDownloader: @unchecked Sendable {
    /// Known Homebrew locations (Apple-silicon + Intel) plus a bare name as a last resort.
    private static let binDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func toolPath(_ name: String) -> String? {
        binDirs.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    /// yt-dlp path + the directory containing ffmpeg, or nil if yt-dlp is missing.
    static func tools() -> (ytdlp: String, ffmpegDir: String?)? {
        guard let yt = toolPath("yt-dlp") else { return nil }
        return (yt, toolPath("ffmpeg").map { ($0 as NSString).deletingLastPathComponent })
    }
    static var isAvailable: Bool { toolPath("yt-dlp") != nil }

    /// Terminal result of a download.
    enum Outcome { case done(URL); case failed(String); case cancelled }

    var onProgress: ((Double, String) -> Void)?          // fraction 0…1, human status
    var onFinished: ((Outcome) -> Void)?

    private let io = DispatchQueue(label: "muninn.videodl")
    private var process: Process?
    private var buffer = Data()
    private var finalURL: URL?
    private var lastError = ""
    private var done = false

    /// Start downloading `url` into `folder`. `audioOnly` → extract MP3, else best video muxed to MP4.
    func start(url: URL, folder: URL, audioOnly: Bool) {
        guard let (ytdlp, ffmpegDir) = Self.tools() else {
            DispatchQueue.main.async { self.onFinished?(.failed("yt-dlp isn't installed")) }
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var args = [
            "--no-playlist", "--newline", "--no-mtime", "--no-part",
            "--retries", "5", "--fragment-retries", "5",
            // YouTube's default client's DASH URLs return HTTP 403 for many videos; the `web_safari`
            // client gives 403-resistant formats without needing a PO token (tv is a low-res fallback).
            // Only affects the youtube extractor — other sites use their defaults.
            "--extractor-args", "youtube:player_client=web_safari,default,tv",
            "-o", folder.appendingPathComponent("%(title).150B [%(id)s].%(ext)s").path,
            "--print", "after_move:filepath",
        ]
        if let ffmpegDir { args += ["--ffmpeg-location", ffmpegDir] }
        args += audioOnly ? ["-x", "--audio-format", "mp3"]
                          : ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
        args.append(url.absoluteString)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ytdlp)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Self.binDirs + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        p.environment = env

        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] h in self?.ingest(h.availableData) }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard let self, !s.isEmpty else { return }
            self.io.async { self.lastError = s.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        p.terminationHandler = { [weak self] proc in
            self?.io.async { self?.finish(status: proc.terminationStatus, out: out, err: err) }
        }
        self.process = p
        do { try p.run() } catch {
            DispatchQueue.main.async { self.onFinished?(.failed("Couldn't launch yt-dlp")) }
        }
    }

    func cancel() { process?.terminate() }

    // MARK: parsing (all on `io`)

    private func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        io.async {
            self.buffer.append(data)
            while let nl = self.buffer.firstIndex(of: 0x0a) {
                let line = String(decoding: self.buffer[self.buffer.startIndex..<nl], as: UTF8.self)
                self.buffer.removeSubrange(self.buffer.startIndex...nl)
                self.parse(line)
            }
        }
    }

    private func parse(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return }
        if let pct = Self.percent(in: line) {
            let frac = pct / 100.0
            DispatchQueue.main.async { self.onProgress?(frac, "Downloading… \(Int(pct))%") }
            return
        }
        if line.contains("[Merger]") || line.contains("[ExtractAudio]") || line.contains("[VideoConvertor]") {
            DispatchQueue.main.async { self.onProgress?(1.0, "Finishing…") }
            return
        }
        // A bare absolute path from `--print after_move:filepath` → the final file.
        if line.hasPrefix("/"), FileManager.default.fileExists(atPath: line) {
            finalURL = URL(fileURLWithPath: line)
        }
    }

    private static func percent(in line: String) -> Double? {
        guard line.contains("[download]"), let r = line.range(of: "%") else { return nil }
        // Take the number immediately before the first '%'.
        let head = line[line.startIndex..<r.lowerBound]
        let num = head.reversed().prefix { $0.isNumber || $0 == "." }.reversed()
        return Double(String(num))
    }

    private func finish(status: Int32, out: Pipe, err: Pipe) {
        guard !done else { return }
        done = true
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        // Drain any tail.
        buffer.append(out.fileHandleForReading.readDataToEndOfFile())
        for line in String(decoding: buffer, as: UTF8.self).split(separator: "\n") { parse(String(line)) }
        let tailErr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if !tailErr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastError = tailErr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let result: Outcome
        if status == 0, let url = finalURL { result = .done(url) }
        else if status == 15 { result = .cancelled }                          // SIGTERM
        else { result = .failed(Self.friendlyError(lastError)) }
        DispatchQueue.main.async { self.onFinished?(result) }
    }

    /// Condense yt-dlp's stderr into a short, human message.
    private static func friendlyError(_ raw: String) -> String {
        let last = raw.split(separator: "\n").last.map(String.init) ?? raw
        var msg = last.replacingOccurrences(of: "ERROR: ", with: "")
        if msg.count > 140 { msg = String(msg.prefix(140)) + "…" }
        return msg.isEmpty ? "Download failed" : msg
    }
}
