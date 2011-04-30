package App::Shotgun::FTP;

# ABSTRACT: App::Shotgun handler for FTP targets

#sub POE::Component::Client::FTP::DEBUG () { 1 };
#sub POE::Component::Client::FTP::DEBUG_COMMAND () { 1 };
#sub POE::Component::Client::FTP::DEBUG_DATA () { 1 };

use MooseX::POE;
use MooseX::Types::Path::Class;
use IO::Handle;
use POE::Component::Client::FTP;

has shotgun => (
	isa => 'App::Shotgun',
	is => 'ro',
	required => 1,
	weak_ref => 1,
	handles => {
		error => '_error',
		ready => '_ready',
		done => '_xferdone',
	},
);

has name => (
	isa => 'Str',
	is => 'rw',
	lazy => 1,
	default => sub {
		my $self = shift;
		return "FTP " . $self->hostname . ":" . $self->port;
	},
);

has hostname => (
	isa => 'Str',
	is => 'ro',
	required => 1,
);

has port => (
	isa => 'Int',
	is => 'ro',
	required => 1,
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

has path => (
	isa => 'Path::Class::Dir',
	is => 'ro',
	coerce => 1,
	predicate => '_has_path',
);

# the file we are currently transferring
has _file => (
	isa => 'Path::Class::File',
	is => 'rw',
	coerce => 1,
);
has _filefh => (
	isa => 'IO::Handle',
	is => 'rw',
);

# directories we know that is on the ftpd
has _knowndirs => (
	traits => ['Hash'],
	isa => 'HashRef[Str]',
	is => 'ro',
	default => sub { {} },
	handles => {
		known_dir => 'exists',
		add_known_dir => 'set',
	},
);

# the state we are in ( init, ready, xfer )
has _state => (
	isa => 'Str',
	is => 'rw',
	default => 'init',
);

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

	POE::Component::Client::FTP->spawn(
		Alias => $self->name,

		RemoteAddr => $self->hostname,
		RemotePort => $self->port,
		Username => $self->username,
		Password => $self->password,
		( $self->usetls ? ( TLS => 1, TLSData => 1 ) : () ),
		ConnectionMode => FTP_PASSIVE, # TODO should we enable control of this?
		Timeout => 120, # TODO is 2m a reasonable number?

		Events => [ qw( all ) ],
	);

	# now we just wait for the connection to succeed/fail
	return;
}

event connected => sub {
	my $self = shift;

	# do nothing hah

	return;
};

event connect_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( $self, "CONNECT - $code $string" );

	return;
};

event login_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( $self, "AUTH - $code $string" );

	return;
};

event authenticated => sub {
	my $self = shift;

	# okay, change to the path for our transfer?
	if ( $self->_has_path ) {
		$self->ftp( 'cd', $self->path->stringify );
	} else {
		# we are now ready to transfer files
		$self->_state( 'ready' );
		$self->ready( $self );
	}

	return;
};

event cd => sub {
	my $self = shift;

	# we are now ready to transfer files
	$self->_state( 'ready' );
	$self->ready( $self );

	return;
};

event cd_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( $self, "CHDIR - $code $string" );

	return;
};

# actually transfer $file from the local dir to the remote
sub transfer {
	my( $self, $file ) = @_;
	$self->_file( $file );
	$self->_state( 'xfer' );

	# Do we need to mkdir the file's path?
	my $dir = $self->_file->dir->stringify;
	if ( $dir ne '.' ) {
		# have we seen this directory before?
		if ( ! $self->known_dir( $dir ) ) {
			# okay, go check it!
			$self->add_known_dir( $dir, 1 );
			$self->ftp( 'mkdir', $dir );
			return;
		}
	}

	# Okay, we are now ready to transfer the file
	$self->ftp( 'type', 'I' );

	return;
};

event mkdir => sub {
	my $self = shift;

	# Okay, we are now ready to transfer the file
	$self->ftp( 'type', 'I' );

	return;
};

event mkdir_error => sub {
	my( $self, $code, $string ) = @_;

	# Did the directory already exist?
	if ( $code eq '521' ) {
		# Okay, move on with the transfer
		$self->ftp( 'type', 'I' );
	} else {
		$self->error( $self, "MKDIR - $code $string" );
	}

	return;
};

event type => sub {
	my $self = shift;

	# okay, we are done with the TYPE command, now we actually send the file!
	$self->ftp( 'put', $self->_file->stringify );

	return;
};

event type_error => sub {
	my( $self, $code, $string ) = @_;

	$self->error( $self, "XFER - $code $string" );

	return;
};

event put_error => sub {
	my( $self, $code, $string, $file ) = @_;

	$self->error( $self, "XFER - $code $string" );

	return;
};

event put_connected => sub {
	my $self = shift;

	# okay, we can send the first block of data!
	my $path = Path::Class::Dir->new( $self->shotgun->source, $self->_file )->stringify;
	if ( open( my $fh, '<', $path ) ) {
		$self->_filefh( $fh );
		$self->yield( 'put_flushed' );
	} else {
		$self->error( $self, "XFER - unable to open $path: $!" );
	}

	return;
};

event put_flushed => sub {
	my $self = shift;

	# read the next block of data from the fh
	my $buf;
	my $retval = read( $self->_filefh, $buf, 10240 ); # TODO is 10240 ok? I lifted it from poco-ftp code
	if ( $retval ) {
		$self->ftp( 'put_data', $buf );
	} elsif ( $retval == 0 ) {
		# all done with the file
		if ( close( $self->_filefh ) ) {
			$self->ftp( 'put_close' );
		} else {
			$self->error( $self,
				"XFER - unable to close " . Path::Class::Dir->new( $self->shotgun->source, $self->_file ) . ": $!"
			);
		}
	} else {
		# error reading file
		$self->error( $self,
			"XFER - unable to read from " . Path::Class::Dir->new( $self->shotgun->source, $self->_file ) . ": $!"
		);
	}

	return;
};

event put_closed => sub {
	my $self = shift;

	# we're finally done with this transfer!
	$self->xferdone( $self, $self->_file );

	return;
};

1;
