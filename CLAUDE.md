# CLAUDE.md

This file provides project guidance for Claude Code and similar coding agents.

## Project Overview

`App::Shotgun` — **mass upload of files via SCP/FTP/… over the wire**.

A Moose-based Dist::Zilla distribution using `[@Author::GETTY]`. It mirrors a target abstraction
over `lib/App/Shotgun/Target/` with concrete `FTP` and `SFTP` transports plus a thin CLI
(`bin/shotgun`) and a Genesis-style example script (`ex/sync.pl`).

## House rules, agents & coordination

Engineering discipline, the delegation lane, and the release policy live in
`.claude/rules/shotgun-rules.md` — auto-loaded by Claude Code at launch. Don't restate them here.

**Delegate behavior-relevant code instead of editing it yourself** (the rule and rationale are in
the rules file). Agents in this repo (their definitions preload the project skills):

| Task | Agent |
|---|---|
| Implement / refactor / debug / behavior-relevant code, new target transports | `shotgun-worker` (default) |
| Write/extend tests under `t/` | `shotgun-worker` |
| Pre-release audit (Changes, cpanfile, dist.ini, build) | `shotgun-release-checker` |

Ticket coordination happens on this repo's karr board (`refs/karr/*`) — `karr list --compact` /
`karr board` for open work. File bugs found here as tickets; the full command surface is in
`.claude/rules/shotgun-rules.md`.

## Architecture

- `lib/App/Shotgun.pm` — main app: MooseX::Getopt attributes, logger (Log::Dispatch), the
  central sync/upload mechanism, an explicit "source" attribute.
- `lib/App/Shotgun/Target.pm` — abstract role (`Moose::Role`) that all targets compose.
- `lib/App/Shotgun/Target/FTP.pm` / `SFTP.pm` — concrete transports. **Both are POE-based**:
  FTP shells out to the native `POE::Component::Client::SimpleFTP` component, while SFTP wraps
  `Net::SFTP::Foreign`/`Expect` in a `POE::Component::Generic` child process — this asymmetry is
  deliberate and must not be "unified" away (see rules).
- `bin/shotgun` — thin CLI entry point.
- `ex/sync.pl` — a standalone (insecure) example script kept as reference for one-shot archive
  syncs; prefer `bin/shotgun` + a target for real work.

## Building and testing

```bash
prove -l t/            # Run all tests; the suite ships no live FTP/SFTP integration tests
dzil test             # Full Dist::Zilla test
dzil build            # Build distribution
```

## Documentation and release notes

- Keep runtime dependencies in `cpanfile`, not `dist.ini`.
- POD follows `[@Author::GETTY]` conventions (inline `=attr`/`=method`, no manual NAME/VERSION/AUTHOR sections).
- `# ABSTRACT:` comment required on every `.pm` file.
- Release policy (`dzil release` only with explicit go-ahead) is in `.claude/rules/shotgun-rules.md`.

## Repository metadata

Agent/skill/rule material lives under `.claude/`:
- `rules/shotgun-rules.md` — house rules, auto-loaded (discipline, delegation, coordination, release, hazards)
- `agents/shotgun-*.md` — the project agent fleet (each definition preloads the project skills)
- `skills/` — `perl-moose`, `perl-release-author-getty`, `perl-release-dist-ini` (hardlinked via
  manage-skills; don't rename, and edit via `cat > .claude/skills/<skill>/SKILL.md` — **not** the
  `Edit`/`Write` tools, which mint a new inode and break the shared hardlink; see skill
  `manage-skills`)

Keep this file focused on the repository; behavioral rules belong in `rules/`, not here.
