# App-Shotgun

Mass upload of files over the wire: a file list goes to one or more targets, FTP or
SFTP, and every file reaches every target on every run. Nothing is compared — no size,
no timestamp, no checksum. That is the name and the promise.

One Moose class, one role, two transports, one CLI — `lib/App/Shotgun.pm`,
`lib/App/Shotgun/Target.pm` (`Moose::Role`), `lib/App/Shotgun/Target/FTP.pm`,
`lib/App/Shotgun/Target/SFTP.pm`, `bin/shotgun` — plus four tests and the example
`ex/sync.pl`. The module map, the sync loop, the target state machine and the known
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

The suite does not run here: `prove -lr t/` fails in all four files because
`MooseX::Types::Path::Class`, `MooseX::Getopt`, `MooseX::LogDispatch`,
`POE::Component::Client::SimpleFTP`, `POE::Component::Generic`,
`MooseX::POE::SweetArgs` and `Expect` are not installed. The suite covers the pure
parts only — the file list, the netrc lookup, the transferlog, the flags — and says
nothing about the transports and nothing about the sync loop.

Six defects are known and recorded on the board: a failed read in the FTP transport
is taken for the end of the file, the target type is loaded with a string eval, the
example script ships a password in the tarball, the sync loop and the transports have
no tests at all, the CLI and module POD are unfinished, and there is no CI.

The release path is blocked as well: there is no `LICENSE` file, so `dzil build`
aborts before it writes an archive.
