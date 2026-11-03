# App::Shotgun

Mass upload of files over FTP or SFTP: every file of a file list reaches every target on every run.

## Description

`App::Shotgun` sends a list of files to one or more targets. Nothing is compared
- no size, no timestamp, no checksum - every file goes to every target, every
time. That is the name and the promise.

Files go up file after file and target after target: the first file reaches all
targets, then the next file follows. With `parallel` all targets receive the
same file at the same time. Missing directories on a target are created as
needed. The first error stops the run, shuts all targets down and leaves
`success` false and `error` set.

Two transports exist: `FTP` and `SFTP`. A target without a `username` takes its
login from `~/.netrc`. SFTP runs with `StrictHostKeyChecking=yes` unless
`ssh_options` say otherwise.

## Installation

```bash
cpanm App::Shotgun
```

## Usage

### From Perl

```perl
use App::Shotgun;

my $shotgun = App::Shotgun->new(
    source => '/path/to/site',
    files  => [ 'robots.txt', 'dir/file.txt', 'index.html' ],
    targets => [
        {
            type     => 'FTP',
            name     => 'Target 1',      # optional
            path     => 'htdocs/',       # optional
            hostname => 'my.local',
            username => 'user',
            password => 'secret',
        },
        {
            type     => 'SFTP',
            name     => 'Target 2',
            path     => '/tmp/testenv',
            hostname => 'myother.local',
            username => 'user',          # key authentication
        },
    ],
);

$shotgun->shot;

print "Success: ", ( $shotgun->success ? 'YES' : 'NO' ), "\n";
print "Error: ", $shotgun->error if !$shotgun->success;
```

The file list comes from `files` / `file`, from a text file with one path per
line (`filelist`), or from the `source` directory (`filerecursive`). Embedded
in a POE-based program, call `shot_poe` instead of `shot` and run the POE
kernel yourself.

### From the command line

```bash
shotgun --filelist a_filelist.txt \
    --target FTP:hostname=localhost:username=testftp:password=test

shotgun --source /path/to/site --file first_file.txt --file second_file.txt \
    --target FTP:hostname=localhost:username=testftp:password=test \
    --target SFTP:hostname=remote.server.com:username=testftp:path=/srv/www
```

Targets are written `type:key=value:key=value...`; a colon cannot be part of a
value. Further options: `--source`, `--filerecursive`, `--parallel` and
`--transferlog` (one line per successful transfer).

### Target attributes

| Attribute | FTP | SFTP |
|---|---|---|
| `name`, `hostname`, `path` | yes | yes |
| `port` | yes | yes |
| `username`, `password` | yes | yes |
| `usetls` | yes | - |
| `ssh_options` | - | yes |

A new transport composes the `App::Shotgun::Target` role.

### Example

`ex/sync.pl` uploads a few files to several FTP and SFTP targets, with the
login taken from `~/.netrc`.

## Development

```bash
prove -lr t/
dzil build
```

## Author

Torsten Raudssus <getty@cpan.org>, Apocalypse <APOCAL@cpan.org>

## License

This software is copyright (c) 2026 by Torsten Raudssus <torsten@raudssus.de>.

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
