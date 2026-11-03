# App-Shotgun

Mass upload of files over the wire: a file list goes to one or more targets, FTP or
SFTP, and every file reaches every target on every run. Nothing is compared — no size,
no timestamp, no checksum. That is the name and the promise.

One Moose class, one role, two transports, one CLI — `lib/App/Shotgun.pm`,
`lib/App/Shotgun/Target.pm` (`Moose::Role`), `lib/App/Shotgun/Target/FTP.pm`,
`lib/App/Shotgun/Target/SFTP.pm`, `bin/shotgun` — plus the tests under `t/` and the
example `ex/sync.pl`. The module map, the sync loop, the target state machine and the known
traps live in skill `app-shotgun-core` — they are not repeated here.

Released to CPAN as `App-Shotgun`, built with `Dist::Zilla` via `[@Author::GETTY]`.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
the principle is a shared house rule (skilletor bundle `getty-cpan-dist@getty`); the lane
boundaries are in `.claude/rules/app-shotgun-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code, new transports | `app-shotgun-worker` (default) |
| Write/extend tests under `t/` | `app-shotgun-worker` |
| Commits, `Changes`, card → done, pre-release audit | `app-shotgun-release-manager` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the
main agent delegates rather than loading them. Skill sources live under
`.claude/skills/` — `getty-perl-core`, `getty-perl-moose`, `getty-perl-pod` and the
karr skills are installed from the shared sources; `app-shotgun-core` is owned by
this repo.

Work is coordinated on the repo's `karr` board (`karr board`).

## State of the code

`prove -lr t/` needs the runtime prerequisites from `cpanfile` installed
(`MooseX::Getopt`, `MooseX::LogDispatch`, `POE::Component::Client::SimpleFTP`,
`POE::Component::Generic`, `MooseX::POE::SweetArgs`, `Net::SFTP::Foreign`, `Expect` …).

The suite covers the pure parts — the file list, the netrc lookup, the transferlog,
the flags — plus the FTP chunk reader, the target type check, the sync loop against
stub targets and the SFTP host key check. `t/08-live-transports.t` walks both
transports against a real server and skips unless `SHOTGUN_TEST_FTP` or
`SHOTGUN_TEST_SFTP` is set.

The release path is the bundle's: `LICENSE` and `Changes` are committed, every module
and `bin/shotgun` carry `our $VERSION`, CI is `.github/workflows/ci.yml` (the shared
`dzil-test` action on Perl 5.36, 5.38 and 5.40), and `ex/sync.pl` carries placeholder
hosts and no credentials.
