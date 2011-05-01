package App::Shotgun::Target;
use strict;
use warnings;

use Moose::Role;
use MooseX::Types::Path::Class;

has shotgun => (
	isa => 'App::Shotgun',
	is => 'ro',
	required => 1,
	weak_ref => 1,
	handles => {
		error => '_error',
		ready => '_ready',
		xferdone => '_xferdone',
		file => 'current_file',
	},
);

has type => (
	isa => 'Str',
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		if ( ref( $self ) =~ /::([^\:]+)$/ ) {
			return $1;
		} else {
			die "Unknown object: $self";
		}
	},
);

=attr name

The name of the target. Set this to something descriptive so you can figure out what went wrong in the logs!

The default is: target_type hostname
Example: "FTP foo.com"

=cut

has name => (
	isa => 'Str',
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		return $self->type . " " . $self->hostname;
	},
);

=attr hostname

The hostname of the target to connect to. Can be a DNS string or ipv4/6 address.

required.

=cut

has hostname => (
	isa => 'Str',
	is => 'ro',
	required => 1,
);

=attr path

The path on the target to consider our "root" directory.

The default is: /

=cut

has path => (
	isa => 'Path::Class::Dir',
	is => 'ro',
	coerce => 1,
	default => Path::Class::Dir->new( '/' ),
);

# the state this target is in
{
	use Moose::Util::TypeConstraints;

	# init means it's still connecting/authenticating to the target
	# ready means it's ready to transfer files
	# testdir means it's testing to see if a path exists on the target
	# dir means it's creating/processing a directory on the target
	# xfer means it's currently transferring a file to the target
	has state => (
		isa => enum( [ qw( init ready testdir dir xfer ) ] ),
		is => 'rw',
		default => 'init',
	);

	no Moose::Util::TypeConstraints;
}

1;
