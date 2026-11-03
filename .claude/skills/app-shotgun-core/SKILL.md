---
name: app-shotgun-core
description: "Load before editing App-Shotgun — the mass upload distribution: the four modules, the POE based FTP and SFTP transports, the sync loop, the target state machine, and the traps in target string parsing, relative paths, file list precedence and the netrc fallback."
---

# App::Shotgun — core

App::Shotgun uploads a list of files to one or more targets over the network. It
compares nothing: no size, no timestamp, no checksum. Every file goes to every
target, every time. That is the name and the promise — a shotgun, not a
synchroniser.

## The distribution

| File | Role |
|---|---|
| `lib/App/Shotgun.pm` | the class: options, the file list, the target list, the sync loop |
| `lib/App/Shotgun/Target.pm` | the role every transport composes: hostname, path, state, known dirs |
| `lib/App/Shotgun/Target/FTP.pm` | the FTP transport |
| `lib/App/Shotgun/Target/SFTP.pm` | the SFTP transport |
| `bin/shotgun` | the CLI: `new_with_options` then `shot` |
| `ex/sync.pl` | a runnable example — not a second implementation |
| `t/*.t` | the suite: load, getopt, logger, features, FTP chunk reader, target type, sync loop, live transports, SFTP host key |

Four modules, one script, one example. There is no plugin registry and no
second object system.

## The object model

`App::Shotgun` is a **Moose class** with the `MooseX::Getopt` role composed —
that is what gives `new_with_options` and the command line flags. Its logger is
a `Log::Dispatch` with `debug`, `info` and `warn` handles; `error` is a plain
attribute of the class, not a logger handle.

`App::Shotgun::Target` is a **`Moose::Role`, not a base class**. `FTP` and
`SFTP` *compose* it with `with qw(App::Shotgun::Target MooseX::LogDispatch)`.
A third transport composes the role too. Nothing in this distribution inherits
from a target class.

The role hands the transports three things: `hostname`, `path` and the
`state` enum, plus the bookkeeping of the directories already known to exist on
the target (`_knowndirs`, starting with `/`).

## The sync loop

`shot` calls `_init` and then runs the POE kernel; `shot_poe` only calls
`_init` and leaves the kernel to an embedding program.

`_init` builds the connections: it makes the target path absolute, looks up
credentials in `~/.netrc` when the target has no username, loads the transport
class and creates one connection per target.

After that the loop is driven by two events:

- `_ready` — a target finished connecting. When **all** targets are ready, the
  first file is handed out.
- `_xferdone` — a target finished a file. The transfer is logged, then either
  the next target gets the same file (serial) or, when every target is done
  again, the next file goes out (parallel).

**Serial** (the default): file after file, target after target — the first file
reaches every target before the second file starts. **Parallel**
(`--parallel`): all targets get the same file at the same time. `current_file`
and `current_connection` are the two counters that carry the position.

`success` is set at the end; `error` holds the first error only — later errors
are deliberately dropped so the message stays readable.

## The target state machine

Each transport walks the same five states:

`init` → `ready` → `testdir` → `dir` → `xfer`

`testdir` is the interesting one: the transport tries to `cd` into the full
directory path of the file. If that fails, the path is created **one level at a
time** (`mkdir`), because many ftpd refuse a `mkdir` with a deep path and want
each level separately. The known-dirs cache keeps the transport from asking
again for a directory it has already created.

## The FTP/SFTP asymmetry is deliberate

Both transports are POE based, but not the same way:

- **FTP** drives `POE::Component::Client::SimpleFTP` natively and streams the
  file itself in 10240 byte chunks.
- **SFTP** spawns `POE::Component::Generic` with `Net::SFTP::Foreign` in a
  child process and hands the whole file over to it.

Every "let's unify these onto one stack" review will flag it. It is a
deliberate keep — the mechanisms are different, not accidental. A new transport
composes the role; it does not replace the two.

## The traps

Four things in this implementation do not do what their shape suggests.

1. **The target string is split on colons.** `FTP:hostname=x:password=a:b` puts
   `a` into the password and turns `b` into a parameter with the value `1`. A
   colon in a password truncates it silently; the login then fails with a
   message that points nowhere near the cause. An `=` in a value is fine — the
   value is rejoined.
2. **A relative target path is resolved against the root.** `path => 'htdocs'`
   becomes `/htdocs`, not `htdocs` below the working directory — the POD
   example suggests the latter.
3. **A file list and a file list together: the second one wins.** The `files`
   builder reads the `filelist` file first and then overwrites the whole list
   with the `file` arguments, if both were given. The filelist content is read
   and thrown away.
4. **The netrc fallback reaches every host.** A target without a username falls
   back to the `default` entry of `~/.netrc` — so the credentials meant for one
   machine are offered to another one.

Two guarantees hold and have tests: a failed read in the FTP transport is an
error, never a finished upload (`t/05-ftp-send-chunk.t`), and the target type
is checked against the known transports `FTP` and `SFTP` before it is loaded —
nothing from the target string is evaluated (`t/06-target-type.t`).

## Vocabulary

- **target** — one destination: a type, a hostname, a path, credentials.
- **transport** — the class that carries out the transfer: `FTP`, `SFTP`.
- **source** — the local directory the file list is relative to.
- **shot** — one run of the whole upload.
- **known dirs** — the directories already confirmed to exist on a target.
- **serial / parallel** — one target at a time, or all targets at once.

## Tests

`prove -lr t/` runs the suite: the module loads, `new_with_options` exists,
no accessor-overwrite warning on load, the pure features (transferlog,
recursive file list, netrc lookup, the parallel flag), the FTP chunk reader,
the target type check, the sync loop against stub targets that never touch the
network, and the SFTP host key check. `t/08-live-transports.t` walks the state
machine of both transports against a real server and skips unless
`SHOTGUN_TEST_FTP` / `SHOTGUN_TEST_SFTP` are set (`host:port:user:pass:basepath`).

Anything that changes the order of the transfers, the directory creation or
the chunked upload needs a test that fails without the change.

## Distribution conventions

- `dist.ini` carries the header and `[@Author::GETTY]`; the requirements live in
  the `cpanfile`, read through `[Prereqs::FromCPANfile]`.
- Every module under `lib/` and `bin/shotgun` carries `our $VERSION`; the bundle
  rewrites it at release through `[RewriteVersion::Transitional]` and
  `[BumpVersionAfterRelease]`.
- `LICENSE`, `Changes` and `README.md` are committed.
- The `Changes` file carries an unreleased `{{$NEXT}}` section with the entries
  of the current work.
- CI is `.github/workflows/ci.yml`.
