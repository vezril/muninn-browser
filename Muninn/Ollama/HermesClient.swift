import Foundation

/// Settings for the local Hermes Agent (Nous Research) integration.
@MainActor
enum HermesSettings {
    private static let pathKey = "hermes.binaryPath"

    /// Path to the `hermes` CLI. Defaults to wherever the installer put it.
    static var binaryPath: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: pathKey), !saved.isEmpty { return saved }
            return discover() ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: pathKey) }
    }

    static var isConfigured: Bool {
        let p = binaryPath
        return !p.isEmpty && FileManager.default.isExecutableFile(atPath: p)
    }

    /// The usual install locations (`install.sh` puts it in `~/.local/bin`).
    static func discover() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/hermes", "/usr/local/bin/hermes", "/opt/homebrew/bin/hermes"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Talks to the LOCAL Hermes Agent by running its CLI one-shot (`hermes -z "<prompt>"`) and
/// forwarding stdout as it arrives. One-shot mode emits only the *final* response, so in practice
/// the answer lands in one or two chunks rather than token-by-token — the chat's typing indicator
/// covers the wait.
///
/// ⚠️ Hermes is an *agent* — it can call tools (shell, files, browser). We deliberately do NOT pass
/// `--yolo`, so its own approval gates stay in force; Muninn only ever hands it a prompt.
struct HermesClient {
    let binaryPath: String

    enum HermesError: LocalizedError {
        case notFound
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Hermes CLI not found. Install it, or set its path in Settings → Models."
            case .failed(let message):
                let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return m.isEmpty ? "Hermes exited with an error." : String(m.prefix(400))
            }
        }
    }

    /// Run a one-shot prompt, streaming output chunks. The stream finishes when Hermes exits.
    func promptStream(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
                continuation.finish(throwing: HermesError.notFound); return
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binaryPath)
            // `-z` is Hermes' one-shot mode: no banner, no spinner, no tool previews — stdout is
            // just the final response text. Tools and memory still run, gated by Hermes' own
            // approval rules (we never pass `--yolo`).
            proc.arguments = ["-z", prompt]

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"      // keep ANSI/TUI escapes out of the transcript
            env["NO_COLOR"] = "1"
            proc.environment = env

            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            let errBuffer = ErrorBuffer()

            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                continuation.yield(text)
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                errBuffer.append(text)
            }

            proc.terminationHandler = { p in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 { continuation.finish() }
                else { continuation.finish(throwing: HermesError.failed(errBuffer.value)) }
            }

            do { try proc.run() } catch { continuation.finish(throwing: error); return }
            continuation.onTermination = { _ in if proc.isRunning { proc.terminate() } }
        }
    }

    /// Flatten a conversation into a single prompt. Hermes keeps its own long-term memory, but each
    /// `-z` run is stateless, so the recent turns travel with the prompt.
    static func prompt(from messages: [ChatMessage]) -> String {
        messages.map { m in
            switch m.role {
            case .system:    return "[context]\n\(m.text)"
            case .user:      return "User: \(m.text)"
            case .assistant: return "Assistant: \(m.text)"
            }
        }.joined(separator: "\n\n")
    }
}

/// Thread-safe accumulator for stderr (the pipe handler runs off the main thread).
private final class ErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) { lock.lock(); text += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
