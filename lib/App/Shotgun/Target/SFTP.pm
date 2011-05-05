package App::Shotgun::Target::SFTP;
use strict;
use warnings;

# ABSTRACT: App::Shotgun target for SFTP servers

use MooseX::POE::SweetArgs;
use POE::Component::Generic;

use Path::Class::Dir;

# argh, we need to fool Test::Apocalypse::Dependencies!
# Also, this will let dzil autoprereqs pick it up without actually loading it...
if ( 0 ) {
	require Net::SFTP::Foreign;
}

with qw(
	App::Shotgun::Target
	MooseX::LogDispatch
);

has port => (
	isa => 'Int',
	is => 'ro',
	default => 22,
);

has username => (
	isa => 'Str',
	is => 'ro',
	required => 1,
);

has password => (
	isa => 'Str',
	is => 'ro',
	predicate => '_has_password',
);

# the poco-generic sftp subprocess
has sftp => (
	isa => 'Maybe[POE::Component::Generic]',
	is => 'rw',
	init_arg => undef,
);

# caches the data we need for this operation
has command_data => (
	isa => 'Any',
	is => 'rw',
	init_arg => undef,
);

# the file we are currently transferring's path entries
has _filedirs => (
	isa => 'ArrayRef[Str]',
	is => 'rw',
	default => sub { [] },
	init_arg => undef,
);

# directories we know that is on the sftp server
has _knowndirs => (
	traits => ['Hash'],
	isa => 'HashRef[Str]',
	is => 'ro',
	init_arg => undef,
	default => sub { {} },
	handles => {
		known_dir => 'exists',
	},
);

sub add_known_dir {
	my( $self, $path ) = @_;

	$self->_knowndirs->{ $path } = 1;
	return;
}

# the master told us to shutdown
sub shutdown {
	my $self = shift;

	# tell poco-generic to shutdown
	if ( defined $self->sftp ) {
		$poe_kernel->call( $self->sftp->session_id, 'shutdown' );
		$self->sftp( undef );
	}

	return;
}

sub START {
	my $self = shift;

	# spawn poco-generic
	$self->sftp( POE::Component::Generic->spawn(
		'alt_fork'		=> 1,	# conserve memory by using exec
		'package'		=> 'Net::SFTP::Foreign',
		'methods'		=> [ qw( error setcwd mkdir put ) ],

		'object_options'	=> [
			host => $self->hostname,
			port => $self->port,

			user => $self->username,
			( $self->_has_password ? ( password => $self->password ) : () ),

			timeout => 120,
		],
		'alias'			=> $self->name,

#		( 'debug' => 1, 'error' => 'sftp_generic_error' ),
	) );

	# check for connection error
	$self->sftp->error( { 'event' => 'sftp_connect' } );

	return;
}

event sftp_generic_error => sub {
	my( $self, $err ) = @_;

	if( $err->{stderr} ) {
		# $err->{stderr} is a line that was printed to the
		# sub-processes' STDERR.  99% of the time that means from
		# your code.
		warn "Got stderr: $err->{stderr}";
	} else {
		# Wheel error.  See L<POE::Wheel::Run/ErrorEvent>
		# $err->{operation}
		# $err->{errnum}
		# $err->{errstr}
		warn "Got wheel error: $err->{operation} ($err->{errnum}): $err->{errstr}";
	}

	return;
};

event _parent => sub { return };
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
		$self->command_data( $dir );
		$self->sftp->setcwd( { 'event' => 'sftp_setcwd' }, $dir );

		return;
	}

	# Okay, we are now ready to transfer the file
	$self->process_put;

	return;
};

sub process_put {
	my $self = shift;

	$self->state( 'xfer' );

	my $localpath = $self->file->absolute( $self->shotgun->source )->stringify;
	my $remotepath = $self->file->absolute( $self->path )->stringify;
	$self->command_data( $remotepath );
	$self->sftp->put( { 'event' => 'sftp_put' }, $localpath, $remotepath );

	# TODO some optimizations to make compatibility better?
#		copy_time => 0,
#		copy_perm => 0,
#		perm => 0755,
}

event sftp_connect => sub {
	my( $self, $err ) = @_;

	# Did we get an error?
	if ( $err ) {
		$self->error( "[" . $self->name . "] CONNECT error: $err" );
	} else {
		# set our cwd so we can initiate the transfer
		$self->sftp->setcwd( { 'event' => 'sftp_setcwd' }, $self->path );
	}

	return;
};

event sftp_setcwd => sub {
	my( $self, $cwd ) = @_;

	if ( $self->state eq 'init' ) {
		# success?
		if ( defined $cwd ) {
			# we're set!
			$self->add_known_dir( $self->path );
			$self->ready( $self );
		} else {
			# get the error!
			$self->sftp->error( { 'event' => 'sftp_setcwd_error' } );
		}
	} elsif ( $self->state eq 'testdir' ) {
		# success?
		if ( defined $cwd ) {
			# we tried to cd to the full path, and it worked!
			$self->_build_filedirs;
			foreach my $d ( @{ $self->_filedirs } ) {
				$self->add_known_dir( $d );
			}

			# Okay, actually start the transfer!
			$self->process_put;
		} else {
			$self->_build_filedirs;

			# if there is only 1 path, we've "tested" it and no need to re-cd into it!
			$self->command_data( $self->_filedirs->[0] );
			if ( scalar @{ $self->_filedirs } == 1 ) {
				# we need to mkdir this one!
				$self->state( 'dir' );
				$self->sftp->mkdir( { 'event' => 'sftp_mkdir' }, $self->_filedirs->[0] );
			} else {
				# we now cd to the first element
				$self->state( 'dir' );
				$self->sftp->setcwd( { 'event' => 'sftp_setcwd' }, $self->_filedirs->[0] );
			}
		}
	} elsif ( $self->state eq 'dir' ) {
		# success?
		if ( defined $cwd ) {
			# Okay, this dir is ok, move on to the next one
			$self->add_known_dir( shift @{ $self->_filedirs } );
			if ( defined $self->_filedirs->[0] ) {
				$self->command_data( $self->_filedirs->[0] );
				$self->ftp( 'cd', $self->_filedirs->[0] );
			} else {
				# finally validated the entire dir path
				$self->process_put;
			}
		} else {
			# we need to mkdir this one!
			$self->command_data( $self->_filedirs->[0] );
			$self->sftp->mkdir( { 'event' => 'sftp_mkdir' }, $self->_filedirs->[0] );
		}
	} else {
		die "(CD) unknown state: " . $self->state;
	}

	return;
};

event sftp_setcwd_error => sub {
	my( $self, $err ) = @_;

	$self->error( "[" . $self->name . "] Error changing to initial path '" . $self->path . "': $err" );

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

event sftp_mkdir => sub {
	my( $self, $result ) = @_;

	if ( $self->state eq 'dir' ) {
		# success?
		if ( $result ) {
			# mkdir the next directory in the filedirs?
			$self->add_known_dir( shift @{ $self->_filedirs } );
			if ( defined $self->_filedirs->[0] ) {
				$self->command_data( $self->_filedirs->[0] );
				$self->sftp->mkdir( { 'event' => 'sftp_mkdir' }, $self->_filedirs->[0] );
			} else {
				# Okay, finally done creating the entire path to the file!
				$self->process_put;
			}
		} else {
			$self->sftp->error( { 'event' => 'sftp_mkdir_error' } );
		}
	} else {
		die "(MKDIR) unknown state: " . $self->state;
	}

	return;
};

event sftp_mkdir_error => sub {
	my( $self, $err ) = @_;

	$self->error( "[" . $self->name . "] MKDIR(" . $self->command_data . ") error: $err" );

	return;
};

event sftp_put => sub {
	my( $self, $result ) = @_;

	# success?
	if ( $result ) {
		# we're finally done with this transfer!
		$self->xferdone( $self );
	} else {
		$self->sftp->error( { 'event' => 'sftp_put_error' } );
	}

	return;
};

event sftp_put_error => sub {
	my( $self, $err ) = @_;

	$self->error( "[" . $self->name . "] XFER(" . $self->command_data . ") error: $err" );

	return;
};

no MooseX::POE::SweetArgs;
__PACKAGE__->meta->make_immutable;
1;
