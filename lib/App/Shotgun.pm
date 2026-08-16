package App::Shotgun;
use strict;
use warnings;

# ABSTRACT: mass upload of files via SCP/FTP/...

use Moose;
use MooseX::Types::Path::Class;
use Cwd qw( getcwd );
use Path::Class::Dir;
use Path::Class::File;
use Log::Dispatch;
use Net::Netrc;

with qw( MooseX::Getopt );

has logger => (
	is      => 'ro',
	isa     => 'Log::Dispatch',
	default => sub {
		Log::Dispatch->new(
			outputs => [
				[ 'Screen', min_level => 'debug', newline => 1 ],
			],
		);
	},
	handles => {
		debug => 'debug',
		info  => 'info',
		warn  => 'warn',
	},
);

=attr transferlog

Path to a file that every successful transfer is logged to, one line per transfer.

If not set, transfers are not logged to a file.

=cut

has transferlog => (
	isa => 'Str',
	is => 'ro',
	predicate => 'has_transferlog',
);

=attr parallel

Enable full parallel uploads to ALL targets at the same time, instead of the
default behaviour of uploading one file to one target at a time.

The default is: 0 ( disabled )

=cut

has parallel => (
	isa => 'Bool',
	is => 'ro',
	default => 0,
);

=attr filerecursive

Get the file list from the source directory, recursively ( like C<ls -lR> ).

The default is: 0 ( disabled )

=cut

has filerecursive => (
	isa => 'Bool',
	is => 'ro',
	default => 0,
);

has source => (
	isa => 'Str',
	is => 'ro',
	default => sub { getcwd },
);

=attr source

The source directory containing the files to upload. Defaults to current working directory.

=cut

has filelist => (
	isa => 'Str',
	is => 'ro',
	predicate => 'has_filelist',
);

=attr filelist

Path to a text file containing list of files to upload (one per line). Alternative to L</file>.

=cut

has file => (
	traits  => ['Array'],
	is      => 'ro',
	isa     => 'ArrayRef[Str]',
	predicate => 'has_file',
);

=attr file

ArrayRef of files to upload. Can be specified multiple times on command line. Alternative to L</filelist>.

=cut

has files => (
	traits  => ['Array'],
	is      => 'ro',
	isa     => 'ArrayRef[Str]',
	lazy    => 1, # must be lazy: the default reads $self->source, which is not
	              # yet initialized when a non-lazy default is evaluated
	default => sub {
		my $self = shift;

		return \@{ $self->_recursive_filelist } if $self->filerecursive;

		my @files;
		my $ok;
		if ( $self->has_filelist ) {
			$ok = 1;
			open( my $fh, '<', $self->filelist ) or die "Unable to open " . $self->filelist . ": $!";
			while ( my $file = <$fh> ) {
				chomp($file);
				push @files, $file;
			}
			close( $fh ) or die "Unable to close " . $self->filelist . ": $!";
		}
		if ( $self->has_file ) {
			$ok = 1;
			@files = @{$self->file};
		}
		$ok ? \@files : die "no files given";
	},
	handles => {
		next_file => 'shift',
		num_files => 'count',
	},
);

=attr files

Internal ArrayRef containing the files to upload. Built from either L</filelist> or L</file>.
When L</filerecursive> is set, the list is instead built by scanning the L</source> directory recursively.

=cut

sub _recursive_filelist {
	my $self = shift;

	my $source = Path::Class::Dir->new( $self->source );

	# We walk the source directory and produce paths relative to the source,
	# matching the relative file list from filelist/file.
	my @files;
	walkdir( dir => $source, rel => undef, files => \@files );
	return \@files;
}

sub walkdir {
	my %args = @_;
	my $root = $args{'dir'};

	for ( $root->children ) {
		my $path = $_;
		my $rel  = defined $args{'rel'} ? $args{'rel'} . "/" . $path->basename : $path->basename;
		if ( $path->is_dir ) {
			walkdir( dir => $path, rel => $rel, files => $args{'files'} );
		} else {
			push @{ $args{'files'} }, $rel;
		}
	}

	return;
}

has targets => (
	traits => ['NoGetopt'],
	is      => 'ro',
	isa     => 'ArrayRef[HashRef[Str]]',
	default => sub {
		my $self = shift;
		if ( $self->has_target ) {
			my @targets;
			for (@{$self->target}) {
				my ($type, @other) = split(/:/,$_);
				my %params;
				for (@other) {
					my ($var, @values) = split(/\=/,$_);
					my $value = @values ? join('=',@values) : 1;
					$params{$var} = $value;
				}
				push @targets, {
					type => $type,
					%params,
				};
			}
			return \@targets;
		} else {
			die "no targets given";
		}
	},
);

=attr targets

Internal ArrayRef of parsed target configurations. Built from L</target>.

=cut

has target => (
	traits  => ['Array'],
	is      => 'ro',
	isa     => 'ArrayRef[Str]',
	predicate => 'has_target',
);

=attr target

ArrayRef of target specification strings. Format: C<type:key=value:key=value...>

Example: C<FTP:hostname=ftp.example.com:username=user:password=pass:path=/htdocs>

=cut

has connections => (
	traits => ['Array','NoGetopt'],
	isa => 'ArrayRef',
	is => 'ro',
	default => sub { [] },
	init_arg => undef,
	handles => {
		new_connection => 'push',
	},
);

=attr connections

Internal ArrayRef of connection objects (instances of C<App::Shotgun::Target::*>).

=cut

has current_connection => (
	traits => ['NoGetopt'],
	isa => 'Int',
	is => 'rw',
	default => 0,
	init_arg => undef,
);

=attr current_connection

Internal counter tracking which connection is currently being used for upload.

=cut

has current_file => (
	traits => ['NoGetopt'],
	isa => 'Path::Class::File',
	is => 'rw',
	coerce => 1,
	init_arg => undef,
);

=attr current_file

Internal attribute tracking the file currently being uploaded.

=cut

has success => (
	traits => ['NoGetopt'],
	isa => 'Bool',
	is => 'rw',
	default => 0,
	init_arg => undef,
);

=attr success

Boolean indicating whether all uploads completed successfully. Check this after calling L</shot>.

=cut

has error => (
	isa => 'Str',
	is => 'rw',
	init_arg => undef,
);

=attr error

Error message if the upload failed. Only set when L</success> is false.

=cut

=method shot

The main entry point of this module.

Returns nothing.

=cut

sub shot {
	my $self = shift;

	$self->_init;

	# fire up the POE kernel
	POE::Kernel->run;

	# All done!
	return;
}

=method shot_poe

Use this method if you are embedding this module in a bigger POE-based program. The only difference with L</shot> is that
this method will not run the POE kernel, leaving it to the caller to do so.

=cut

sub shot_poe {
	my $self = shift;

	$self->_init;

	return;
}

sub _init {
	my $self = shift;

	$self->logger->debug( "Starting SHOTGUN" );
	
	# TODO: Checking if there is any [^|/].{1,2}[$|/] in the files

	die "No targets defined" if ! scalar @{ $self->targets };

	# construct all of our connection targets
	foreach my $t ( @{ $self->targets } ) {
		if ( ! exists $t->{'type'} ) {
			die "type missing from target info";
		}

		# convert the path to an absolute path
		if ( exists $t->{'path'} ) {
			$t->{'path'} = Path::Class::Dir->new( $t->{'path'} )->absolute( '/' );
		}

		# pull user/pass from a .netrc file if a username was not given explicitly
		if ( ! exists $t->{'username'} ) {
			my $netrc = $self->_netrc_credentials( $t->{'hostname'} );
			$t->{'username'} = $netrc->{'username'} if ! exists $t->{'username'} && defined $netrc->{'username'};
			$t->{'password'} = $netrc->{'password'} if ! exists $t->{'password'} && defined $netrc->{'password'};
		}

		my $type = delete $t->{'type'};
		eval "use App::Shotgun::Target::$type";
		if ( $@ ) {
			die "Unknown target type: $type - $@";
		} else {
			my $connection = "App::Shotgun::Target::$type"->new( %$t, shotgun => $self );
			$self->new_connection( $connection );
		}
	}
}

sub _netrc_credentials {
	my( $self, $hostname ) = @_;

	return {} if ! defined $hostname;

	my $mach = Net::Netrc->lookup( $hostname );
	if ( ! $mach ) {
		# try the default entry
		$mach = Net::Netrc->lookup( 'default' );
	}
	return {} if ! $mach;

	my %ret;
	$ret{'username'} = $mach->login    if defined $mach->login;
	$ret{'password'} = $mach->password if defined $mach->password;
	return \%ret;
}

sub _log_transfer {
	my( $self, $target ) = @_;

	return if ! $self->has_transferlog;

	open( my $fh, '>>', $self->transferlog ) or do {
		$self->logger->warn( "Unable to open transferlog '" . $self->transferlog . "': $!" );
		return;
	};
	print {$fh} scalar( localtime ) . " " . $target->name . " " . $self->current_file . "\n";
	close( $fh ) or $self->logger->warn( "Unable to close transferlog '" . $self->transferlog . "': $!" );

	return;
}

sub _error {
	my( $self, $error ) = @_;

	# ignore stacked errors
	return if defined $self->error;

	$self->logger->debug( "ERROR: $error" );
	$self->error( $error . "\n" );

	# Tell all of our targets to shutdown
	foreach my $t ( @{ $self->connections } ) {
		$t->yield( 'shutdown' );
	}

	return;
}

sub _ready {
	my( $self, $target ) = @_;

	# target is ready, set it's state
	# convenience, really - so I don't have to type this in all the targets :)
	$self->logger->debug( "Target [" . $target->name . "] is ready" );
	$target->state( 'ready' );

	# $target is now ready for transfer, are all of our targets ready?
	foreach my $t( @{ $self->connections } ) {
		if ( $t->state ne 'ready' ) {
			return;
		}
	}

	# got here, all of our targets are ready!
	# start the process by transferring the first file!
	$self->current_file( $self->next_file );

	if ( $self->parallel ) {
		# fire up a transfer on ALL targets at the same time
		foreach my $c ( @{ $self->connections } ) {
			$c->yield( 'transfer' );
		}
	} else {
		$self->connections->[ $self->current_connection ]->yield( 'transfer' );
	}

	return;
}

sub _xferdone {
	my( $self, $target ) = @_;

	# target finished transferring
	# convenience, really - so I don't have to type this in all the targets :)
	$self->logger->debug( "Target [" . $target->name . "] finished transferring '" . $self->current_file . "'" );
	$target->state( 'ready' );

	# log this transfer to the transferlog file if configured
	$self->_log_transfer( $target );

	if ( $self->parallel ) {
		# are all of our targets done with the current file?
		foreach my $t( @{ $self->connections } ) {
			if ( $t->state ne 'ready' ) {
				return;
			}
		}

		# got here, all targets are done with the current file
		if ( $self->num_files ) {
			# fire up the next file on all targets at the same time
			$self->current_file( $self->next_file );
			foreach my $c ( @{ $self->connections } ) {
				$c->yield( 'transfer' );
			}
		} else {
			# SHOTGUN DONE
			$self->success( 1 );

			# Tell all of our targets to shutdown
			foreach my $t ( @{ $self->connections } ) {
				$t->yield( 'shutdown' );
			}
		}

		return;
	}

	# Okay, move on to the next connection
	$self->current_connection( $self->current_connection + 1 );
	if ( ! defined $self->connections->[ $self->current_connection ] ) {
		# finished sending this file to all connections!
		# do we have more files to send?
		if ( $self->num_files ) {
			# process the next file
			$self->current_connection( 0 );
			$self->current_file( $self->next_file );
			$self->connections->[ $self->current_connection ]->yield( 'transfer' );
		} else {
			# SHOTGUN DONE
			$self->success( 1 );

			# Tell all of our targets to shutdown
			foreach my $t ( @{ $self->connections } ) {
				$t->yield( 'shutdown' );
			}
		}
	} else {
		# Tell the next connection to process the file
		$self->connections->[ $self->current_connection ]->yield( 'transfer' );
	}

	return;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=pod

=head1 SYNOPSIS

	use App::Shotgun;

	my $shotgun = App::Shotgun->new(
		source => '../relative/path',
		files => [
			# NEVER NEVER EVER EVER use relative paths here!
			# They should be in the source path
			'robots.txt',
			'dir/dir/dir/file.txt',
			'category/index.html',
			'index.html',
		],
		targets => [
			{
				type => 'FTP',
				name => 'Target 1', # optional
				path => 'htdocs/', # optional
				hostname => 'my.local',
				username => 'notfor',
				password => 'you321',
			},
			{
				type => 'SFTP',
				name => 'Target 2', # optional
				path => '/tmp/testenv', # optional
				hostname => 'myother.local',
				username => 'notfor',

				# prepared key authentifications are just working
				# probably more options for configuring ssh, like alternative private key
			},
		],
	);

	# Order of upload:
	# Target 1: robots.txt
	# Target 2: robots.txt
	# Target 1: dir/dir/dir/file.txt
	# Target 2: dir/dir/dir/file.txt
	# ...

	$shotgun->shot;

	print "Success: ".($shotgun->success ? 'YES' : 'NO')."\n";
	print "Error: ".$shotgun->error if (!$shotgun->success);

	my $other_shotgun = App::Shotgun->new(
		source => '/absolute/path',
		filelist => 'filelist.txt',
	);

=head1 DESCRIPTION

This module uploads the filelist textfile given via L</filelist> or the filelist given as array via L</files> to all given L</targets>.
It uploads file after file, to target after target, that means, first file will get uploaded to all target, and if they all are
successful done, the next file will be uploaded. This module doesn't do any "smart" things like compare filesize/modification time/etc and
just uploads the files. Hence the name "shotgun" which is appropriate.

For first the module is made to try again very often but will not continue on fail and close with an exit code above 0.

Please look at the appropriate C<App::Shotgun::Target::*> classes for their attributes and how to use them.

=cut
