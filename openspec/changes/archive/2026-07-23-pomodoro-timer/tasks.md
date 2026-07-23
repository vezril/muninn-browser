# Tasks: pomodoro-timer

- [x] `PomodoroEngine` + `PomodoroConfig` + `PomodoroSettings` — state machine, pure `Pomodoro.next`
      transition rule, persisted config.
- [x] `PomodoroTool` — progress ring (`PomodoroRingView`), start/pause/reset/skip, session dots, inline
      customize steppers (`LabeledStepper`) + auto-start.
- [x] Phase-end feedback: sound + in-app toast (foreground) + OS notification (backgrounded); auth on
      first Start; engine keeps ticking when not the visible tab.
- [x] `AppShell` — register tool in the Tools sidebar; `revealPomodoro` + palette command.
- [x] `PomodoroEngineTests` (7): transition rule, long-break-every-N, tick/complete, apply-config, reset.
- [x] Build clean; full suite green (110); live-gated.
