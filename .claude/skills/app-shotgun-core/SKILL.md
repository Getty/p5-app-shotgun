---
name: app-shotgun-core
description: "Load before editing App-Shotgun — the mass upload distribution: the four modules, the POE based FTP and SFTP transports, the sync loop, the target state machine, and the traps that a failed read counts as the end of the file and that the target string is loaded with a string eval."
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
| `t/01-load.t` … `t/04-features.t` | the suite: load, getopt, logger, features |

Four modules, one script, one example. There is no plugin registry and no
second object system.

## The object model

`App::Shotgun` is a **Moose class** with the `MooseX::Getopt` role composed —
that is what gives `new_with_options` and the command line flags. Its logger is
a `Log::Dispatch` with `debug`, `info` and `warn` handles; `error` is a plain
attribute of the class, not a logger handle (an earlier version had both and
Moose warned about the collision).

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

Seven things in this implementation do not do what their shape suggests. They
are known, they are not fixed, and they are on the board.

1. **A failed read is taken for the end of the file.** In the FTP transport,
   `read` returns `undef` on error and `0` at the end of the file. The code
   asks `if ($retval)` first, and `undef` is false — so the error case falls
   into the `elsif ($retval == 0)` branch and the transfer is closed as
   **successful**. The file on the server is truncated at the point of the
   error and nobody is told. The error branch of the code is unreachable.
2. **The target type is loaded with a string eval.** `_init` runs
   `eval "use App::Shotgun::Target::$type"` with `$type` taken from the target
   string. A `;` inside the value ends the `use` and the rest of the value is
   executed as Perl code.
3. **The example script carries a password and an internal host.** `ex/sync.pl`
   contains a real password and a private address, and `ex/` is not excluded
   from the distribution — the credentials end up in the CPAN tarball.
4. **The target string is split on colons.** `FTP:hostname=x:password=a:b` puts
   `a` into the password and turns `b` into a parameter with the value `1`. A
   colon in a password truncates it silently; the login then fails with a
   message that points nowhere near the cause. An `=` in a value is fine — the
   value is rejoined.
5. **A relative target path is resolved against the root.** `path => 'htdocs'`
   becomes `/htdocs`, not `htdocs` below the working directory — the POD
   example suggests the latter.
6. **A file list and a file list together: the second one wins.** The `files`
   builder reads the `filelist` file first and then overwrites the whole list
   with the `file` arguments, if both were given. The filelist content is read
   and thrown away.
7. **The netrc fallback reaches every host.** A target without a username falls
   back to the `default` entry of `~/.netrc` — so the credentials meant for one
   machine are offered to another one.

## Vocabulary

- **target** — one destination: a type, a hostname, a path, credentials.
- **transport** — the class that carries out the transfer: `FTP`, `SFTP`.
- **source** — the local directory the file list is relative to.
- **shot** — one run of the whole upload.
- **known dirs** — the directories already confirmed to exist on a target.
- **serial / parallel** — one target at a time, or all targets at once.

## Tests

`prove -lr t/` runs four files: the module loads, `new_with_options` exists,
no accessor-overwrite warning on load, and the pure features — transferlog,
recursive file list, netrc lookup, the parallel flag.

The suite says nothing about the transports and nothing about the sync loop.
Anything that changes the order of the transfers, the directory creation or
the chunked upload needs a test that fails without the change.

## Distribution conventions

- `dist.ini` uses `[@Author::GETTY]`, the requirements live in the `cpanfile`.
- The modules carry **no** `our $VERSION` — the version comes from the git
  tags through `@Git::VersionManager` and is stamped into the build.
- There is no `LICENSE` file in the repository, so `dzil build` aborts before
  it writes an archive.
- The `Changes` file carries an unreleased section with the entries of the
  current work.
