# ADR-002 — Egress-Audit Harness (Reusable, No TLS Interception)

**Status:** Accepted (needs spike — S5: verify `eproc` attribution on macOS 26 **and** that per-datastore `proxyConfigurations` actually routes the background host's service-worker-style fetches; also picks mitmdump vs bespoke logger)
**Date:** 2026-07-11
**Source IDs:** NFR-5, FR-19, FR-21, FR-22, NFR-8, E8, E11
**Evidence:** `openspec/changes/architecture-and-adrs/research/2.3-egress-audit-tooling.md`

## Context

NFR-5 gates M1 exit (and recurs at later milestones) on a host-level allowlist audit of **shell/shim-originated** traffic, with page-initiated traffic recorded but not gated. Two hard sub-problems: **attribution** (WKWebView traffic egresses from the shared `com.apple.WebKit.Networking` XPC service — Apple provides almost no API to resolve responsibility) and **classification** (no network-level tool can distinguish the shim's background-host fetch from a page subresource fetch to the same host). The audit needs only `(destination host, originating class)` — never payloads. Apple services fail closed under HTTPS interception, and decrypting `*.proton.me` would violate ground rule 1. Precedent: Brave's checked-in `network-audit` (allowlist + checker script) is the shape that stayed useful; one-off manual setups did not.

## Decision

Build a small **reusable harness in `audit/`** with two independent layers that must agree, and **no TLS MITM anywhere**:

1. **Attribution (outside the app):** `sudo tcpdump -i pktap,<iface> -k NP -w session.pcapng` — macOS's pktap metadata carries `proc` *and* `eproc` (delegated/responsible process), attributing WebKit XPC traffic back to the host app; post-process with tshark ≥ 4.6 into `(host ← DNS/SNI, proc, eproc, pid)` tuples. Hostnames only; encrypted payloads never parsed.
2. **Classification (inside the app, debug flag `MUNINN_EGRESS_AUDIT=1`):** per-`WKWebsiteDataStore` `proxyConfigurations` (macOS 14+) routes the background-host store, page-tab store, and native `URLSession` traffic to **distinct local logger ports** — classification becomes a port number, not a heuristic. Loggers are host-recording only (`mitmdump --ignore-hosts '.*' --show-ignored-hosts` or a ~50-line bespoke CONNECT logger; spike decides).
3. **Checker:** PASS iff every host on the shim/native ports matches `audit/egress-allowlist.txt` AND every pcap-attributed flow is explained by exactly one logger — an unexplained flow is an automatic FAIL (it means instrumentation coverage broke, which is precisely the bug the audit exists to catch).

Checked-in artifacts: `audit/egress-allowlist.txt` (annotated per-host rationale), `audit/run-egress-audit.sh` (embeds the ground-rule-2 GUI-launch confirmation gate), `audit/session-script.md` (fixed scenario; login/unlock performed by Calvin per ground rule 1), generated `audit/report-YYYY-MM-DD.md`. Raw `.pcapng` is gitignored and deleted post-report (it is a browsing record).

## Consequences

- The credential ground rule is satisfied **by construction**: no CA is ever generated or installed; `ignore-hosts '.*'` is hardcoded; the in-app logger records method + host only for Proton hosts (no paths, queries, bodies, headers).
- The data-store separation this requires is the same separation architecture §6 wants for reliability — one mechanism, two benefits. The in-app hooks land with E1/E3 (~50 lines); harness v1 is 1–2 days; per-milestone reruns ~30 minutes.
- **Two load-bearing unverified facts, both in spike S5** (½–1 day, toy app, GUI-warning applies), verified before E8 relies on the harness: (a) `eproc` delegation for `com.apple.WebKit.Networking` on macOS 26 (documented on older macOS) — fallback if it fails: PID-tree snapshot filtering, classification layer unaffected; (b) per-datastore `proxyConfigurations` routing the *background host's* fetches — if the hidden host's traffic bypasses the proxy, the deterministic classification claim collapses; fallback: classify shim traffic by destination-host + PID join from layer 1, degrading classification from structural to inferential (recorded in the report as such).
- Known blind spots, accepted and recorded: hostnames come from DNS/SNI, so ECH or in-app DoH would blind layer 1 (neither applies to Proton/Apple hosts today — re-check at each audit); `sudo` is required for capture.
- Little Snitch remains recommended as Calvin's *personal continuous* monitor between audits, but the milestone gate does not depend on a commercial GUI tool.
