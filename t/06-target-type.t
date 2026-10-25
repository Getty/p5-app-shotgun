#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use_ok( 'App::Shotgun' );

# the target type comes from the command line: only the known transports may
# be loaded, and nothing in the value may be executed.
our $PWNED;

for my $type ( 'Nope', 'FTP; $main::PWNED = 1', 'FTP::../Evil', '' ) {
	local $PWNED;
	my $shotgun = App::Shotgun->new(
		file    => ['foo'],
		targets => [ { type => $type, hostname => 'localhost', username => 'u', password => 'p' } ],
	);

	eval { $shotgun->_init };
	like( $@, qr/^Unknown target type: \Q$type\E \(known: FTP, SFTP\)/, "type '$type' is refused with a clear message" );
	ok( ! defined $PWNED, "type '$type' executed nothing" );
	is( scalar @{ $shotgun->connections }, 0, "type '$type' created no connection" );
}

done_testing;
