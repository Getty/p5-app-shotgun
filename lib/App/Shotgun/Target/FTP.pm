package App::Shotgun::Target::FTP;
use strict;
use warnings;

# ABSTRACT: App::Shotgun target for FTP servers

#sub POE::Component::Client::SimpleFTP::DEBUG () { 1 };

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

event _child => sub { return };

# actually transfer $file from the local dir to the remote
sub transfer {
	my $self = shift;
	$self->state( 'xfer' );

	$self->logger->debug( "Target [" . $self->name . "] starting transfer of '" . $self->file . "'" );

	# Do we need to mkdir the file's path?
	my $dir = $self->file->dir->absolute( $self->path )->stringify;
	if ( ! $self->known_dir( $dir ) ) {
		# okay, go check it!
		$self->state( 'testdir' );
		$self->ftp( 'cd', $dir );

		return;
	}

	# Okay, we are now ready to transfer the file
	$self->ftp( 'put', $self->file->absolute( $self->path )->stringify );

	return;
};

event connected => sub {
	my $self = shift;

	# do nothing hah

	return;
};

event connect_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] CONNECT error: $code $string" );

	return;
};

event login_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( "[" . $self->name . "] LOGIN error: $code $string" );

	return;
};

event authenticated => sub {
	my $self = shift;

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
	my( $self, $code, $reply, $path ) = @_;

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
		$self->ftp( 'put', $self->file->absolute( $self->path )->stringify );
	} elsif ( $self->state eq 'dir' ) {
		# Okay, this dir is ok, move on to the next one
		$self->add_known_dir( shift @{ $self->_filedirs } );
		if ( defined $self->_filedirs->[0] ) {
			$self->ftp( 'cd', $self->_filedirs->[0] );
		} else {
			# finally validated the entire dir path
			$self->state( 'xfer' );
			$self->ftp( 'put', $self->file->absolute( $self->path )->stringify );
		}
	} else {
		die "(CD) unknown state: " . $self->state;
	}

	return;
};

event cd_error => sub {
	my( $self, $code, $reply, $path ) = @_;

	if ( $self->state eq 'init' ) {
		$self->error( "[" . $self->name . "] Error changing to initial path '$path': $code $reply" );
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
	my( $self, $code, $reply, $path ) = @_;

	if ( $self->state eq 'dir' ) {
		# mkdir the next directory in the filedirs?
		$self->add_known_dir( shift @{ $self->_filedirs } );
		if ( defined $self->_filedirs->[0] ) {
			$self->ftp( 'mkdir', $self->_filedirs->[0] );
		} else {
			# Okay, finally done creating the entire path to the file!
			$self->ftp( 'put', $self->file->absolute( $self->path )->stringify );
		}
	} else {
		die "(MKDIR) unknown state: " . $self->state;
	}

	return;
};

event mkdir_error => sub {
	my( $self, $code, $reply, $path ) = @_;

	$self->error( "[" . $self->name . "] MKDIR($path) error: $code $reply" );

	return;
};

event put_error => sub {
	my( $self, $code, $reply, $path ) = @_;

	$self->error( "[" . $self->name . "] XFER($path) error: $code $reply" );

	return;
};

event put_connected => sub {
	my( $self, $path ) = @_;

	# okay, we can send the first block of data!
	my $localpath = $self->file->absolute( $self->shotgun->source )->stringify;
	if ( open( my $fh, '<', $localpath ) ) {
		$self->_filefh( $fh );

		# send the first chunk
		$self->send_chunk;
	} else {
		$self->error( "[" . $self->name . "] XFER($path) error: unable to open $localpath: $!" );
	}

	return;
};

event put_flushed => sub {
	my( $self, $path ) = @_;

	# read the next chunk of data from the fh
	$self->send_chunk;

	return;
};

sub send_chunk {
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

event put => sub {
	my( $self, $code, $reply, $path ) = @_;

	# we're finally done with this transfer!
	$self->xferdone( $self );

	return;
};

no MooseX::POE::SweetArgs;
__PACKAGE__->meta->make_immutable;
1;
