# App-Shotgun House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Mass upload of files via SCP/FTP/… — one class, one role, two transports. Read first: the
callers of the seam you change — the class, the role, the two transports, `bin/shotgun`.

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code, new transports | `app-shotgun-worker` (default) |
| Write/extend tests under `t/` | `app-shotgun-worker` |
| Commits, `Changes`, card → done, pre-release audit | `app-shotgun-release-manager` |
| Read-only research, audit, gap analysis | `app-shotgun-worker` ("read-only, change nothing") |

Behavior-relevant = the sync loop, the transports and the state machine, the file and target
lists, the CLI, the tests — not prose or changelog wording.

## Deviations from the house rules

- A topic raised on the public GitHub tracker becomes an internal karr card; the issue itself
  stays untouched.

## Hazards

- **The transfer order is the product — don't regress it silently.** Upload file after file,
  target after target; with `--parallel`, all targets get the same file at once. The state
  machine `init → ready → testdir → dir → xfer` and the known-dirs cache keep a transport from
  asking the server twice. A change to any of that is user-visible: it needs a `Changes` entry
  and a test. Contract: skill `app-shotgun-core`.
- **The suite is silent on the transports and the sync loop.** Every change to the transfer
  order, the directory creation or the upload needs a test that fails without it.
- **The FTP/SFTP asymmetry is a deliberate keep** — do not unify the two stacks without a card.
- **One class, one role, two transports.** A third transport composes the role; a plugin
  system needs a card that asks for it.

## Perl specifics — reference, don't restate

Moose and cpanfile pinning: `getty-perl-core`, `getty-perl-moose`. POD: `getty-perl-pod`.
Release path: `perl-release-dist-ini`, `getty-perl-release-author-getty`. Module map, sync loop,
state machine, traps: skill `app-shotgun-core`.
