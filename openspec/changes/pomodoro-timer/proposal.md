# Proposal: pomodoro-timer

A customizable **Pomodoro timer** as a Tools-sidebar tool (the intended home for glanceable utilities).

## What it does

A new **Pomodoro** tool (right Tools sidebar, `timer` icon; also ⌘N → "Pomodoro Timer"):
- A **progress ring** with the live MM:SS countdown and a phase label — **Focus / Short Break / Long
  Break**, each colour-coded (accent / teal / green).
- **Start/Pause · Reset · Skip** controls; the Start button reads Start/Resume/Pause by state.
- **Session dots** showing focus sessions completed toward the next long break.
- Auto-advances Focus → break → Focus; a long break lands after every N focus sessions.
- On each phase change: a **sound**, an **in-app toast** (when Muninn is foreground), and a **macOS
  notification** banner (when backgrounded) — no double-alert (foreground suppresses the OS banner; the
  OS banner is silent since the sound covers audio). Permission is requested on first Start.
- The engine keeps ticking even when the tool isn't the visible tab (the view is retained by the shell).

**Customize** (slider icon in the tool) reveals steppers for Focus / Short break / Long break durations,
"Long break every N", and an "Auto-start next" toggle. All persist via `PomodoroSettings` (UserDefaults);
the running timer resets on relaunch.

## Design

- `PomodoroEngine` — the state machine (phase, remaining, completedFocus, running) driven by a 1-second
  `tick()`; the phase-transition rule (`Pomodoro.next`) is pure and unit-tested. `PomodoroConfig` +
  `PomodoroSettings` hold/persist the durations.
- `PomodoroTool` — the view: `PomodoroRingView` (CAShapeLayer ring), `LabeledStepper` rows, controls,
  dots, and the notification/sound wiring.

## Impact

New `Muninn/Pomodoro/` (`PomodoroEngine`, `PomodoroTool`). `AppShell` registers the tool, wires the
phase-end toast, and adds a `revealPomodoro` + palette command. 110 XCTests green (+7
`PomodoroEngineTests`); live-gated (countdown, transitions, sound, toast, OS notification, customize).
