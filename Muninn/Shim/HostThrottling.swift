import Foundation
import WebKit
import os

/// Stops WebKit from throttling the hidden background host's JS timers.
///
/// Mechanism (traced to WebKit source + verified against the macOS 26.2 SDK by the
/// webkit-developer investigation, 2026-07-12): a window-less WKWebView's timers are
/// starved by two *process-level* mechanisms — not by DOM-timer throttling (which a
/// DedicatedWorker escapes, since `WorkerGlobalScope` doesn't override
/// `domTimerAlignmentInterval`):
///   1. RunningBoard suspension (UI-process) → `WKPreferences.inactiveSchedulingPolicy`
///      defaults to `.suspend` for macOS-14+-linked apps; `.none` keeps the process alive.
///      **PUBLIC** API.
///   2. App Nap (content-process) → `_setAppNapEnabled(false)`. **SPI** — gated behind
///      `allowsPrivateAPI` so an App Store build can omit it (ADR-003).
///
/// Because the RunningBoard throttle is a *per-process, one-way latch*, the host must run
/// in its own WebContent process (a dedicated `WKWebsiteDataStore` guarantees this).
///
/// The arm is selectable via `MUNINN_THROTTLE_ARM` (A|B|C|D) so the bisect can attribute
/// the fix to a specific lever (A = negative control).
enum HostThrottling {
    private static let log = Logger(subsystem: "com.vezril.Muninn", category: "HostThrottling")

    /// The 4-arm bisect (2026-07-12) showed the PUBLIC lever alone (arm B,
    /// `inactiveSchedulingPolicy = .none`) fully restores timer fidelity
    /// (125/120 ticks vs the 4/120 default baseline), so the shipping path uses
    /// ZERO private API. The SPI App-Nap lever remains gated here for the bisect
    /// / future use only; a dev run enables it with MUNINN_THROTTLE_ARM=C|D and
    /// this flag flipped.
    static let allowsPrivateAPI = false

    /// Stable identifier for the host's dedicated data store (process isolation).
    private static let hostStoreID = UUID(uuidString: "6D756E69-6E6E-4261-6B67-486F73740001")!

    enum Arm: String { case A, B, C, D }

    static var arm: Arm {
        Arm(rawValue: ProcessInfo.processInfo.environment["MUNINN_THROTTLE_ARM"] ?? "B") ?? .B
    }

    static func apply(to config: WKWebViewConfiguration, host: BackgroundHost) {
        // Dedicated WebContent process (all arms) — the throttle latch is per-process.
        if #available(macOS 14.0, *) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: hostStoreID)
        }

        let arm = self.arm
        // Lever B — PUBLIC. Keep the process off RunningBoard suspension.
        if arm == .B || arm == .D {
            if #available(macOS 14.0, *) {
                config.preferences.inactiveSchedulingPolicy = .none
            }
        }
        // Lever C — SPI. Disable App Nap for the content process.
        if (arm == .C || arm == .D) && allowsPrivateAPI {
            setAppNapEnabled(false, on: config.preferences)
        }
        log.notice("throttling arm \(arm.rawValue, privacy: .public) applied")
    }

    // MARK: - SPI

    private typealias SetBoolIMP = @convention(c) (AnyObject, Selector, ObjCBool) -> Void

    /// `-[WKPreferences _setAppNapEnabled:]` (SPI). KVC can't reach it (it would probe
    /// `set_appNapEnabled:`), so call the IMP directly.
    private static func setAppNapEnabled(_ enabled: Bool, on preferences: WKPreferences) {
        let selector = Selector(("_setAppNapEnabled:"))
        guard let method = class_getInstanceMethod(WKPreferences.self, selector) else {
            log.error("SPI _setAppNapEnabled: missing — host may App Nap")
            return
        }
        let fn = unsafeBitCast(method_getImplementation(method), to: SetBoolIMP.self)
        fn(preferences, selector, ObjCBool(enabled))
    }
}
