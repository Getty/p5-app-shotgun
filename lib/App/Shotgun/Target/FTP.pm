package App::Shotgun::Target::FTP;
use strict;
use warnings;

# ABSTRACT: App::Shotgun target for FTP servers

sub POE::Component::Client::SimpleFTP::DEBUG () { 1 };

use MooseX::POE::SweetArgs;
use MooseX::Types::Path::Class;
use POE::Component::Client::SimpleFTP;

with qw(
	App::Shotgun::Target
	MooseX::LogDispatch
);

has port => (
	isa => 'Int',
	is => 'ro',
	default => 21,
);

has usetls => (
	isa => 'Bool',
	is => 'ro',
	default => 0,
);

has username => (
	isa => 'Str',
	is => 'ro',
	required => 1,
);

has password => (
	isa => 'Str',
	is => 'ro',
	required => 1,
);

# the file we are currently transferring
has _filefh => (
	isa => 'Ref',
	is => 'rw',
	init_arg => undef,
);
has _filedirs => (
	isa => 'ArrayRef[Str]',
	is => 'rw',
	default => sub { [] },
	init_arg => undef,
);

# directories we know that is on the ftpd
has _knowndirs => (
	traits => ['Hash'],
	isa => 'HashRef[Str]',
	is => 'ro',
	init_arg => undef,
	default => sub {
		return {
			# obviously the root exists... :)
			'/' => 1,
		};
	},
	handles => {
		known_dir => 'exists',
	},
);

sub add_known_dir {
	my( $self, $path ) = @_;

	$self->_knowndirs->{ $path } = 1;
	return;
}

# convenience function to simplify passing events to poco-ftp
sub ftp {
	my( $self, @args ) = @_;

	# don't print the actual data we upload, as it can be binary or whatever
	if ( $args[0] ne 'put_data' ) {
		$self->logger->debug( 'sending command(' . $args[0] . ') to ftpd with data(' . ( defined $args[1] ? $args[1] : '' ) . ')' );
	} else {
		$self->logger->debug( 'sending command(' . $args[0] . ') to ftpd' );
	}

	$poe_kernel->post( $self->name, @args );

	return;
}

# the master told us to shutdown
sub shutdown {
	my $self = shift;

	# disconnect from the ftpd
	$self->ftp( 'quit' );

	return;
}

sub START {
	my $self = shift;

	POE::Component::Client::SimpleFTP->new(
		alias => $self->name,

		remote_addr => $self->hostname,
		remote_port => $self->port,
		username => $self->username,
		password => $self->password,
		( $self->usetls ? ( tls_cmd => 1, tls_data => 1 ) : () ),
	);

	# now we just wait for the connection to succeed/fail
	return;
}

# actually transfer $file from the local dir to the remote
sub transfer {
	my $self = shift;
	$self->state( 'xfer' );

	$self->logger->debug( "starting transfer of " . $self->file );

	# Do we need to mkdir the file's path?
	my $dir = $self->file->dir->absolute( $self->path )->stringify;
	if ( ! $self->known_dir( $dir ) ) {
		# okay, go check it!
		$self->state( 'testdir' );
		$self->ftp( 'cd', $dir );

		return;
	}

	# Okay, we are now ready to transfer the file
	$self->ftp( 'type', 'I' );

	return;
};

event connected => sub {
	my $self = shift;

	# do nothing hah
	$self->logger->debug( "connected" );

	return;
};

event connect_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] CONNECT error: $code $string" );

	return;
};

event login_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] AUTH error: $code $string" );

	return;
};

event authenticated => sub {
	my $self = shift;

	$self->logger->debug( "authenticated" );

	# okay, change to the path for our transfer?
	if ( $self->path->stringify ne '/' ) {
		$self->ftp( 'cd', $self->path->stringify );
	} else {
		# we are now ready to transfer files
		$self->ready( $self );
	}

	return;
};

sub _build_filedirs {
	my $self = shift;

	my @dirs;
	foreach my $d ( $self->file->dir->dir_list ) {
		if ( ! defined $dirs[0] ) {
			push( @dirs, Path::Class::Dir->new( $self->path, $d )->stringify );
		} else {
			push( @dirs, Path::Class::Dir->new( $dirs[-1], $d )->stringify );
		}
	}

	# Weed out the known directories
	foreach my $d ( @dirs ) {
		if ( ! $self->known_dir( $d ) ) {
			push( @{ $self->_filedirs }, $d );
		}
	}

	return;
}

event cd => sub {
	my $self = shift;

	if ( $self->state eq 'init' ) {
		# we are now ready to transfer files
		$self->add_known_dir( $self->path->stringify );
		$self->ready( $self );
	} elsif ( $self->state eq 'testdir' ) {
		# we tried to cd to the full path, and it worked!
		$self->_build_filedirs;
		foreach my $d ( @{ $self->_filedirs } ) {
			$self->add_known_dir( $d );
		}

		# Okay, actually start the transfer!
		$self->state( 'xfer' );
		$self->ftp( 'type', 'I' );
	} elsif ( $self->state eq 'dir' ) {
		# Okay, this dir is ok, move on to the next one
		$self->add_known_dir( shift @{ $self->_filedirs } );
		if ( defined $self->_filedirs->[0] ) {
			$self->ftp( 'cd', $self->_filedirs->[0] );
		} else {
			# finally validated the entire dir path
			$self->state( 'xfer' );
			$self->ftp( 'type', 'I' );
		}
	} else {
		die "(CD) unknown state: " . $self->state;
	}

	return;
};

event cd_error => sub {
	my( $self, $code, $string ) = @_;

	$self->logger->debug( "CHDIR error: $code $string" );

	if ( $self->state eq 'init' ) {
		$self->error( "[" . $self->name . "] CHDIR error: $code $string" );
	} elsif ( $self->state eq 'testdir' ) {
		# we have to cd/mkdir EACH directory path to be compatible with many ftpds
		# we store the full path here, so we can always be sure it's a valid path ( CWD issues )
		# on a vsftpd 2.2.0 ftpd:
		#ftp> mkdir /lib
		#257 "/lib" created
		#ftp> mkdir /lib/App
		#257 "/lib/App" created
		#ftp> mkdir /lib/App/Shotgun/Foo
		#550 Create directory operation failed.
		#ftp>
		$self->_build_filedirs;

		# if there is only 1 path, we've "tested" it and no need to re-cd into it!
		if ( scalar @{ $self->_filedirs } == 1 ) {
			# we need to mkdir this one!
			$self->state( 'dir' );
			$self->ftp( 'mkdir', $self->_filedirs->[0] );
		} else {
			# we now cd to the first element
			$self->state( 'dir' );
			$self->ftp( 'cd', $self->_filedirs->[0] );
		}
	} elsif ( $self->state eq 'dir' ) {
		# we need to mkdir this one!
		$self->ftp( 'mkdir', $self->_filedirs->[0] );
	}

	return;
};

event mkdir => sub {
	my $self = shift;

	$self->logger->debug( "MKDIR OK" );

	if ( $self->state eq 'dir' ) {
		# mkdir the next directory in the filedirs?
		$self->add_known_dir( shift @{ $self->_filedirs } );
		if ( defined $self->_filedirs->[0] ) {
			$self->ftp( 'mkdir', $self->_filedirs->[0] );
		} else {
			# Okay, finally done creating the entire path to the file!
			$self->ftp( 'type', 'I' );
		}
	} else {
		die "(MKDIR) unknown state: " . $self->state;
	}

	return;
};

event mkdir_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] MKDIR error: $code $string" );

	return;
};

event type => sub {
	my $self = shift;

	$self->logger->debug( "TYPE ok" );

	# okay, we are done with the TYPE command, now we actually send the file!
	$self->ftp( 'put', $self->file->absolute( $self->path )->stringify );

	return;
};

event type_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] XFER error: $code $string" );

	return;
};

event put_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] XFER error: $code $string" );

	return;
};

event put_server => sub {
	my $self = shift;

	# do nothing hah
	$self->logger->debug( "PUT connected" );

	return;
};

event put_connected => sub {
	my $self = shift;

	$self->logger->debug( "PUT connected" );

	# okay, we can send the first block of data!
	my $path = $self->file->absolute( $self->shotgun->source )->stringify;
	if ( open( my $fh, '<', $path ) ) {
		$self->_filefh( $fh );

		# send the first chunk
		$self->do_read_file;
	} else {
		$self->error( "[" . $self->name . "] XFER error: unable to open $path: $!" );
	}

	return;
};

event put_flushed => sub {
	my $self = shift;

	$self->logger->debug( "PUT flushed" );

	# read the next chunk of data from the fh
	$self->do_read_file;

	return;
};

sub do_read_file {
	my $self = shift;

	my $buf;
	my $retval = read( $self->_filefh, $buf, 10240 ); # TODO is 10240 ok? I lifted it from poco-ftp code
	if ( $retval ) {
		$self->ftp( 'put_data', $buf );
	} elsif ( $retval == 0 ) {
		# all done with the file
		if ( close( $self->_filefh ) ) {
			$self->ftp( 'put_close' );
		} else {
			$self->error( "[" . $self->name . "] XFER error: unable to close " . $self->file->absolute( $self->shotgun->source )->stringify . ": $!" );
		}
	} else {
		# error reading file
		$self->error( "[" . $self->name . "] XFER error: unable to read from " . $self->file->absolute( $self->shotgun->source )->stringify . ": $!" );
	}

	return;
}

event put_closed => sub {
	my $self = shift;

	$self->logger->debug( "PUT closed" );

	return;
};

event put_done => sub {
	my $self = shift;

	# we're finally done with this transfer!
	$self->xferdone( $self );

	return;
};

no MooseX::POE::SweetArgs;
__PACKAGE__->meta->make_immutable;
1;
