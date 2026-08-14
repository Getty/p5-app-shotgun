# App::Shotgun House Rules

Apply to every task in this repository unless explicitly overridden. Bias: caution over speed
on non-trivial work; use judgment on trivial tasks. Loaded automatically by Claude Code at
launch (same priority as `CLAUDE.md`). Subagents get their discipline from the skills
force-loaded via `briefing.skills` — this file is for the orchestrating agent.

## Engineering discipline

1. **Think before coding** — State assumptions. When uncertain, ask rather than guess. Present
   alternatives when ambiguous. Push back when a simpler approach exists. Stop when confused;
   name what's unclear.
2. **Simplicity first** — Minimum code that solves the problem. Nothing speculative. No
   abstractions for single-use code.
3. **Surgical changes** — Touch only what you must. Don't "improve" adjacent code, comments, or
   formatting. Match existing style.
4. **Read before you write** — Before new code, read the caller/side of the seam you are about
   to change: `lib/App/Shotgun.pm`, `lib/App/Shotgun/Target/*.pm`, `bin/shotgun`. "Looks
   orthogonal" is dangerous.
5. **Tests verify intent, not just behavior** — A test that can't fail when the logic changes is
   wrong. Reproduce a bug before fixing it; leave a regression test behind.
6. **Match the codebase's conventions, even if you disagree** — Conformance > taste. Surface a
   harmful convention; don't fork silently.
7. **Fail loud** — "Done" is wrong if anything was skipped silently. "Tests pass" is wrong if any
   were skipped. Surface uncertainty, don't hide it.
8. **A red test is a claim before it is a failure** — Before changing code to turn a test green,
   say out loud what the test asserts and whether your fix keeps that claim or replaces it. If
   the claim is wrong, fix the claim and say so; don't quietly make the code match a wrong claim.

## Delegation

Depends on whether the Agent/Task tool is available to you.

- **You can spawn subagents** (orchestrating main agent): Do NOT touch behavior-relevant code
  yourself — delegate to this repo's worker. Your lane: coordinate, inspect, plan, review diffs,
  run tests, manage git, edit non-behavioral docs. Why: only the `shotgun-*` agents get their
  skills force-loaded via `briefing.skills`; you get no briefing and would touch internals with
  too little context. Specialist lanes:

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug / behavior-relevant code, new targets | `shotgun-worker` (default) |
  | Write/extend tests under `t/` | `shotgun-worker` |
  | Pre-release audit (Changes, cpanfile, dist.ini, build) | `shotgun-release-checker` |

- **You cannot spawn subagents** (you ARE a `shotgun-*` agent): The delegation lock does not
  apply — implement, refactor, debug, and test per these rules.

Behavior-relevant = target transport logic (`Target/*`), the sync mechanism in
`lib/App/Shotgun.pm`, CLI behavior in `bin/shotgun`, error handling, tests. Pure prose docs and
changelog notes are not.

## Coordination — karr board (always in scope)

Shotgun tracks its work on its own karr board (`refs/karr/*`) once `karr init` has run — karr is
always in scope, don't invoke a skill first, just use it:

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --tags a,b --body '…'` — new ticket
- `karr edit ID -a "note"` · `--claim NAME` · `--block "why"` — update
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note "…"` — to review
- mutating commands auto-sync; `karr sync --pull|--push` for explicit exchange

Bugs found while working become tickets on this board. Full command surface: skill `karr`.

**Serialize board mutations when fanning out.** Keep implementation parallel if you like, but
collect results and then loop `karr move`/`handoff`/`sync` sequentially — N of them landing at
once is a resource event, not a cheap command.

## Release — never without permission

`prove -l t/` / `dzil build` / `dzil test` are fine anytime. `dzil release` and any CPAN upload
are STRICTLY forbidden without the maintainer's explicit go-ahead — even if a plan or STATUS
document lists "release" as the next step. After a release, the `$VERSION` bump in
`lib/App/Shotgun.pm` is a separate, deliberate commit.

## Project-specific hazards

- **The FTP/SFTP transport asymmetry is a deliberate keep.** FTP is event-driven (POE:
  `POE::Component::Client::SimpleFTP`, `MooseX::POE::SweetArgs`); SFTP is synchronous
  (`Net::SFTP::Foreign`, `Expect`). Every naive "let's unify these onto one stack" review will
  flag it — don't let it be refactored away without an ADR-style justification. Adding a third
  transport means a new `Target::*` subclass, not re-architecting the core.
- **Keep the suite thin by intent.** `t/01-load.t` is minimal on purpose; deep integration tests
  need a live FTP/SFTP server and are not part of the default run. Don't add a heavyweight
  harness.

## Perl specifics — reference, don't restate

Moose patterns live in skill `perl-moose`; release/dist-zilla conventions in
`perl-release-author-getty` and `perl-release-dist-ini` (force-loaded for `shotgun-*` agents).
Do not duplicate that content here.
