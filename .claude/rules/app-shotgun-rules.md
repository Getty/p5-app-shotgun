# App-Shotgun House Rules

Apply to every task in this repo unless explicitly overridden. Bias: caution over speed
on non-trivial work; use judgment on trivial tasks. Loaded automatically at launch, same
priority as `CLAUDE.md`. The subagents get their conventions from the force-loaded
skills — this file is for the orchestrating agent.

## Engineering discipline

1. **Think before coding** — State assumptions. When uncertain, ask rather than guess.
   Push back when a simpler approach exists. Name what is unclear.
2. **Simplicity first** — One class, one role, two transports. A third transport
   composes the role; a plugin system needs a card that asks for it.
3. **Surgical changes** — Touch only what you must. Don't "improve" adjacent code,
   comments or formatting. Match the existing layout.
4. **Read before you write** — Read the callers of the seam you change: the class,
   the role, the two transports, `bin/shotgun`.
5. **Tests verify intent** — The suite is silent on the transports and the sync loop.
   Every change to the transfer order, the directory creation or the upload needs a
   test that fails without it.
6. **Match the codebase's conventions, even if you disagree** — Conformance > taste.
   Surface a harmful convention; don't fork silently.
7. **Fail loud** — "Done" is wrong if something was skipped silently. "Tests pass" is
   wrong if any were skipped. Surface uncertainty, don't hide it.

## Delegation

- **You can spawn subagents** (orchestrating main agent): Do NOT touch behavior-relevant
  code yourself — delegate. Your lane: coordinate, inspect, plan, review diffs, run
  tests, edit non-behavioral docs. Why: only the `app-shotgun-*` agents get their
  skills force-loaded via `briefing.skills`; you get no briefing and would touch the
  transfer order and the chunked upload with too little context.

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug behavior-relevant code, new transports | `app-shotgun-worker` (default) |
  | Write/extend tests under `t/` | `app-shotgun-worker` |
  | Commits, `Changes`, card → done, pre-release audit | `app-shotgun-release-manager` |

- **You cannot spawn subagents** (you ARE an `app-shotgun-*` agent): the delegation
  lock does not apply — implement, refactor, debug and test per these rules.

Behavior-relevant = the sync loop, the transports and the state machine, the file and
target lists, the CLI, the tests — not prose or changelog wording. **Only
`app-shotgun-release-manager` commits**: a worker leaves a commit-ready tree and hands
its card to `review`; the release-manager cuts the commit and closes it.

## The transfer order is the product — don't regress it silently

Upload file after file, target after target; with `--parallel`, all targets get the
same file at once. The state machine `init → ready → testdir → dir → xfer` and the
known-dirs cache keep a transport from asking the server twice. A change to any of
that is user-visible: it needs a `Changes` entry and a test. The FTP/SFTP asymmetry
is a deliberate keep — do not unify the two stacks without a card. Contract: skill
`app-shotgun-core`.

## Coordination — karr board (always in scope)

Ticket coordination is the orchestrating agent's job, so `karr` is always in scope — just use it, don't invoke the skill first. Board state lives in `refs/karr/*`.

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --tags a,b --body '…'` — new ticket
- `karr edit ID -a "note"` · `--claim NAME` · `--block "why"` — update
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note "…"` — to review
- mutating commands auto-sync; `karr sync --pull|--push` for explicit exchange

Life cycle: you claim and hand out → the worker notes and ends at `review` → the
release-manager commits and moves the card to `done`.

**Serialize board mutations when fanning out.** Keep implementation work parallel, then
loop the board writes one after another — N at once is a resource event, not cheap.

## Release — never without permission

`prove -lr t/` / `dzil build` / `dzil test` are fine anytime. `dzil release`, a tag
and any CPAN upload are STRICTLY forbidden without the maintainer's explicit
go-ahead — even if a plan lists "release" as the next step. Stop and ask.

## Public trackers — never act without instruction

`karr` is the internal agent board, churned freely. The GitHub issue tracker carries
real people's reports under the maintainer's account. Never act on a public issue on
your own initiative — not even to read it. Listing, viewing, commenting, closing and
creating are off without an explicit instruction; the topic becomes an internal card.

## Perl specifics — reference, don't restate

Moose and cpanfile pinning: `getty-perl-core`, `getty-perl-moose`. POD: `getty-perl-pod`.
Release path: `perl-release-dist-ini`, `getty-perl-release-author-getty`. Module map, sync
loop, state machine, traps: skill `app-shotgun-core`. Do not duplicate them here.
