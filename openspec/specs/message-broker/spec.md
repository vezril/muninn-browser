# message-broker Specification

## Purpose
TBD - created by archiving change e2-e3-shim-core. Update Purpose after archive.
## Requirements
### Requirement: Runtime message round-trip
The shim SHALL route `runtime.sendMessage` from any registered context (content-script world, extension page, background host) through the native broker to its destination and deliver the response back to the sender, preserving Chrome's callback/promise duality and `lastError` semantics.

#### Scenario: Content-to-background round-trip
- **WHEN** a test content context calls `browser.runtime.sendMessage(payload)` and the background context's `onMessage` listener replies
- **THEN** the sender's promise resolves with the reply, and envelope routing metadata (sender identity) is correct

#### Scenario: Dead-recipient surfaces lastError
- **WHEN** a message is sent while the background host is terminated (pre-watchdog-restart)
- **THEN** the sender observes a rejected promise / `lastError`, not a hang

### Requirement: Persistent ports (DEFERRED to E6)
The shim SHALL implement `runtime.connect`/`onConnect` with broker-owned port state: ordered, at-most-once delivery per port, disconnect events on context destruction, and survival across many exchanges.

> **Scope note (Calvin, 2026-07-12):** full port semantics require a *second* live context (content script/page) to exchange with; that context first exists in E6. This requirement is therefore built and verified in **E6**, not e2-e3-shim-core. Until then the broker rejects `connect` cleanly (no hang, no crash). The scenarios below are E6 acceptance.

#### Scenario: Port survives sustained exchange
- **WHEN** a port is opened and 50 interleaved messages are exchanged in both directions
- **THEN** all messages arrive exactly once, in per-direction order, and the port remains connected (FR-10's ≥5-exchange acceptance exceeded deliberately)

#### Scenario: Disconnect on context teardown
- **WHEN** the context holding one end of a port is destroyed
- **THEN** the other end's `onDisconnect` fires within a bounded interval

### Requirement: Payload opacity
The broker SHALL treat message payloads as opaque — routing decisions, logs, and any debug output use envelope fields only; payload bytes are never parsed, logged, or persisted by Muninn code (FR-21, NFR-8, ADR-007).

#### Scenario: Debug logging excludes payloads
- **WHEN** broker debug logging is enabled and messages flow
- **THEN** the log contains envelope metadata (kind, msgId, sender, sizes) and zero payload content — verified by sending a known sentinel string and grepping the log for it

### Requirement: Inert onMessageExternal surface
`runtime.onMessageExternal.addListener` SHALL succeed without error and never fire (the fork.js reframe supersedes the mechanism; registration must not throw per FR-11's acceptance).

#### Scenario: Listener registration is harmless
- **WHEN** background code registers an `onMessageExternal` listener at boot
- **THEN** no error is thrown and no event is ever delivered to it

