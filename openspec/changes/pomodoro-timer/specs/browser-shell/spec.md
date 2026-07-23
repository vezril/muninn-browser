# browser-shell

## ADDED Requirements

### Requirement: Pomodoro timer
Muninn SHALL provide a customizable Pomodoro timer as a Tools-sidebar tool, cycling focus and break
phases with a visible countdown, controls to start/pause/reset/skip, and phase-change alerts.

#### Scenario: run a focus/break cycle
- **WHEN** the user starts the timer
- **THEN** the current phase counts down, and on reaching zero it advances to the next phase (a long break
  after every configured number of focus sessions) with a sound and a notification

#### Scenario: customize durations
- **WHEN** the user changes the focus/break durations, long-break interval, or auto-start setting
- **THEN** the timer uses and persists those settings

#### Scenario: alert while in another app
- **WHEN** a phase completes while Muninn is in the background and notifications are permitted
- **THEN** a system notification announces the transition
