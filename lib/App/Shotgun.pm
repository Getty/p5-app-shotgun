package App::Shotgun;
# ABSTRACT: mass upload of files via SCP/FTP/...

use MooseX::POE;
use Cwd qw( getcwd );

with qw(
	MooseX::Getopt
);

# TODO unimplemented
#has transferlog => (
#	isa => 'Str',
#	is => 'ro',
#	predicate => 'has_transferlog',
#);

has source => (
	isa => 'Str',
	is => 'ro',
	default => sub { getcwd },
);

has filelist => (
	isa => 'Str',
	is => 'ro',
	predicate => 'has_filelist',
);

has files => (
	traits  => ['Array'],
	is      => 'ro',
	isa     => 'ArrayRef[Str]',
	default => sub {
		my $self = shift;
		if ( $self->has_filelist ) {
			my @files;
			open( my $fh, '<', $self->filelist ) or die "Unable to open " . $self->filelist . ": $!";
			while ( my $file = <$fh> ) {
				push @files, $file;
			}
			close( $fh ) or die "Unable to close " . $self->filelist . ": $!";
			return \@files;
		} else {
			die "no files given";
		}
	},
	handles => {
		next_file => 'shift',
		num_files => 'count',
	},
);

has targets => (
	is      => 'ro',
	isa     => 'ArrayRef[HashRef[Str]]',
	required => 1,
);

# the state we are in ( start, xfer )
has _state => (
	isa => 'Str',
	is => 'rw',
	default => 'start',
);

has _connections => (
	isa => 'ArrayRef',
	is => 'ro',
	default => sub { [] },
);

has _current_connection => (
	isa => 'Int',
	is => 'rw',
	default => 0,
);

has success => (
	isa => 'Bool',
	is => 'rw',
	default => 0,
);

has error => (
	traits => ['Array'],
	isa => 'ArrayRef[Str]',
	is => 'ro',
	default => sub { [] },
	handles => {
		_add_error => 'push',
	},
);

sub shot {
	my $self = shift;

	# construct all of our connection targets
	foreach my $t ( @{ $self->targets } ) {
		if ( ! exists $t->{'type'} ) {
			die "type missing from target info";
		}

		my $type = delete $t->{'type'};
		eval "require App::Shotgun::$type";
		if ( $@ ) {
			die "Unknown target type: $type - $@";
		} else {
			my $connection = "App::Shotgun::$type"->new( %$t );
			$self->_connections->push( $connection );
		}
	}

	# fire up the POE kernel
	POE::Kernel->run;

	# All done!
	return;
}

sub _error {
	my( $self, $target, $error ) = @_;

	if ( $self->_state eq 'start' ) {
		$self->_add_error( "Error connecting to(" . $target->name . "): $error" );
	} else {
		$self->_add_error( "Error transferring file(" . $target->_file . ") to(" . $target->name . "): $error" );
	}

	# Tell all of our targets to shutdown
	foreach my $t ( @{ $self->_connections } ) {
		$t->shutdown;
	}

	return;
}

sub _ready {
	my( $self, $target ) = @_;

	# $target is now ready for transfer, is all of our targets ready?
	foreach my $t( @{ $self->_connections } ) {
		if ( $t->_state ne 'ready' ) {
			return;
		}
	}

	# got here, all of our targets are ready!
	# transfer the first file
	$self->_state( 'xfer' );
	$self->_connections->[ $self->_current_connection ]->transfer( $self->next_file );

	return;
}

sub _xferdone {
	my( $self, $target, $file ) = @_;

	# Okay, move on to the next connection
	$self->_current_connection( $self->_current_connection + 1 );
	if ( ! defined $self->_connections->[ $self->_current_connection ] ) {
		# finished sending this file to all connections!
		# do we have more files to send?
		if ( $self->num_files ) {
			# process the next file
			$self->_current_connection( 0 );
			$self->_connections->[ $self->_current_connection ]->transfer( $self->next_file );
		} else {
			# SHOTGUN DONE
			$self->success( 1 );

			# Tell all of our targets to shutdown
			foreach my $t ( @{ $self->_connections } ) {
				$t->shutdown;
			}
		}
	} else {
		# Tell the next connection to process the file
		$self->_connections->[ $self->_current_connection ]->transfer( $file );
	}

	return;
}

1;

=head1 SYNOPSIS

  use App::Shotgun;

  my $shotgun = App::Shotgun->new(
    transferlog => 'transfer.log', # optional
    source => '../relative/path',
    files => [
      'robots.txt',
      'dir/dir/dir/file.txt',
      'category/index.html',
      'index.html',
    ],
    targets => [
      {
        name => 'Target 1', # optional
	path => 'htdocs/', # optional
        type => 'FTP',
        hostname => 'my.local',
        username => 'notfor',
        password => 'you321',
      },
      {
        name => 'Target 2', # optional
        type => 'SCP',
		dir => '/tmp/testenv', # optional
		# Type specific:
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
  ä Target 2: dir/dir/dir/file.txt
  # ...

  $shotgun->shot;

  print "Success: ".($shotgun->success ? 'YES' : 'NO')."\n";
  print "Error: ".$shotgun->error if (!$shotgun-success);

  my $other_shotgun = App::Shotgun->new(
    source => '/absolute/path',
    filelist => 'filelist.txt',
  );

=head1 DESCRIPTION

This module uploads the filelist textfile given via B<filelist> or the filelist given as array via B<files> to all given B<targets>.
It uploads file after file, to target after target, that means, first file will get uploaded to all target, and if they all are
successful done, the next file will be uploaded.

For first the module is made to try again very often but will not continue on fail and close with an exit code above 0.
