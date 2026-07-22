import AppKit
import SwiftUI
@preconcurrency import Translation
import NaturalLanguage

/// On-device page translation via Apple's `Translation` framework — no page text ever leaves the Mac
/// (unlike Chrome/Edge, which POST content to Google/Microsoft). The framework's `TranslationSession`
/// is only vended through a SwiftUI modifier (`.translationTask`), so we host a zero-size SwiftUI view
/// in the window and drive it from AppKit. First use of a language pair triggers Apple's own on-device
/// model download UI (attached to our window) — we don't build that.
@MainActor
final class PageTranslator {
    static let shared = PageTranslator()

    private let model = TranslationModel()
    private var hosting: NSView?

    enum TranslateError: Error { case sameLanguage(String), unsupported(String) }

    /// Add the offscreen SwiftUI host to `window`'s content view (once). Must be in a live window so
    /// the framework can present its download sheet and run the translation task.
    func attach(to window: NSWindow) {
        guard hosting == nil, let content = window.contentView else { return }
        let host = NSHostingView(rootView: TranslationHostView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        host.alphaValue = 0.0                 // invisible but in-hierarchy (0-size clips it anyway)
        content.addSubview(host, positioned: .below, relativeTo: nil)
        hosting = host
    }

    /// Best-effort dominant-language detection over a text sample (BCP-47, e.g. "fr", "en").
    static func detectLanguage(_ sample: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(sample)
        return r.dominantLanguage?.rawValue
    }

    /// Translate `texts` into `targetCode` (e.g. "en"). `sourceCode` nil → auto-detected from the batch.
    /// Returns translations positionally aligned with `texts` (untranslatable entries pass through).
    func translate(_ texts: [String], to targetCode: String, from sourceCode: String?) async throws -> [String] {
        let target = Locale.Language(identifier: targetCode)
        let source = sourceCode.map { Locale.Language(identifier: $0) }

        // Availability check — surface a clear message instead of a silent no-op.
        if let source {
            let status = await LanguageAvailability().status(from: source, to: target)
            if status == .unsupported {
                throw TranslateError.unsupported(Locale.current.localizedString(forLanguageCode: sourceCode ?? "") ?? (sourceCode ?? "that language"))
            }
        }
        return try await model.run(texts: texts, source: source, target: target)
    }
}

/// A Sendable translation error carried back across the actor boundary.
struct TranslationFailure: Error { let message: String }

/// Bridges an `async` batch request to the SwiftUI `.translationTask` session. One job at a time
/// (page translation is a discrete user action); the actual `session.translations` calls run in the
/// (nonisolated) task closure so only Sendable values (`[String]`) cross the MainActor boundary.
@MainActor
final class TranslationModel: ObservableObject {
    @Published var config: TranslationSession.Configuration?

    private struct Job {
        let texts: [String]
        let continuation: CheckedContinuation<[String], Error>
    }
    private var job: Job?

    func run(texts: [String], source: Locale.Language?, target: Locale.Language) async throws -> [String] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String], Error>) in
            self.job = Job(texts: texts, continuation: cont)
            // Toggle to nil first so an identical (source,target) still re-fires the task.
            self.config = nil
            DispatchQueue.main.async {
                self.config = TranslationSession.Configuration(source: source, target: target)
            }
        }
    }

    /// The pending batch's source strings (MainActor state), or nil if there's no job.
    func pendingTexts() -> [String]? { job?.texts }

    /// Resolve the pending job (MainActor state) and clear it.
    func finish(_ result: Result<[String], TranslationFailure>) {
        guard let job else { return }
        self.job = nil
        switch result {
        case .success(let out): job.continuation.resume(returning: out)
        case .failure(let err): job.continuation.resume(throwing: err)
        }
    }
}

private struct TranslationHostView: View {
    @ObservedObject var model: TranslationModel

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(model.config) { session in
                guard let texts = await model.pendingTexts() else { return }
                do {
                    let out = try await Self.translateBatch(session, texts: texts)
                    await model.finish(.success(out))
                } catch {
                    await model.finish(.failure(TranslationFailure(message: error.localizedDescription)))
                }
            }
    }

    /// Nonisolated so the (non-Sendable) `session` and the per-chunk `requests` stay in one isolation
    /// region — building and consuming the requests here avoids a cross-actor send. Chunked so a single
    /// request stays modest on large pages. Only the Sendable `[String]` result crosses back.
    private nonisolated static func translateBatch(_ session: TranslationSession, texts: [String]) async throws -> [String] {
        let chunkSize = 64
        var out = texts                                          // pass-through defaults
        for start in stride(from: 0, to: texts.count, by: chunkSize) {
            let end = min(start + chunkSize, texts.count)
            let requests = (start..<end).map {
                TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0))
            }
            let responses = try await session.translations(from: requests)
            for r in responses {
                if let cid = r.clientIdentifier, let i = Int(cid), i < out.count {
                    out[i] = r.targetText
                }
            }
        }
        return out
    }
}
