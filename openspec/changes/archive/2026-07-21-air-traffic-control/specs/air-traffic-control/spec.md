# air-traffic-control

## ADDED Requirements

### Requirement: Links to a bound host open in that host's workspace
A routing rule SHALL bind a host to a workspace. When a URL is opened through a
user-facing entry point and a rule matches the URL's host, Muninn SHALL open the URL in
the rule's workspace — switching to that workspace (and thereby its profile) when it is
not already active — instead of the currently active workspace.

#### Scenario: an external link routes to its bound space
- **WHEN** Muninn is the default browser and another app opens `https://youtube.com/watch?v=…`
  while the active space is a different one, and a rule binds `youtube.com` to space "Media"
- **THEN** Muninn switches to "Media" and opens the link in a new tab there

#### Scenario: the address bar routes to a bound space
- **WHEN** the user types a URL in the sidebar address bar whose host matches a rule pointing
  at a different space
- **THEN** Muninn switches to that space and opens the URL in a new tab there (rather than
  loading it in the current tab)

#### Scenario: the command tool routes to a bound space
- **WHEN** the user opens a URL from the command tool whose host matches a rule pointing at
  a different space
- **THEN** Muninn switches to that space and opens the URL in a new tab there

#### Scenario: subdomains match the bound host
- **WHEN** a rule binds `github.com` and a link to `gist.github.com` is opened
- **THEN** the rule matches and the link routes (a `www.` prefix on either side is ignored)

#### Scenario: no rule matches
- **WHEN** the opened URL's host matches no rule
- **THEN** behaviour is unchanged: address-bar/command-tool URLs open normally and an
  external link opens in a Quick Look window

#### Scenario: the rule targets the already-active space
- **WHEN** the URL matches a rule whose workspace is already the active one
- **THEN** no space switch occurs and the URL loads in place (address bar) as normal

#### Scenario: the rule targets a deleted space
- **WHEN** a rule references a workspace that no longer exists
- **THEN** the rule is ignored and the URL opens with default behaviour

### Requirement: Routing rules are user-managed in Settings and persist
The Settings window SHALL provide a Routing section to add, edit the host of, retarget, and
remove rules. Rules SHALL persist across relaunch.

#### Scenario: add, edit, and remove a rule
- **WHEN** the user adds a rule, types a host, picks a target space, and later clicks remove
- **THEN** each change takes effect immediately and survives an app relaunch

#### Scenario: rules survive relaunch
- **WHEN** rules exist and Muninn is relaunched
- **THEN** the rules are still present and still route
