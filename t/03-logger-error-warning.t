#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

# The logger attribute's `handles => { error => 'error' }` used to collide
# with the locally defined `error` attribute, producing
# "You are overwriting a locally defined method (error) with an accessor"
# on every load. That warning is now gone; guard against it regressing.
my @warnings;
{
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    require App::Shotgun;
}
ok( ! grep { /overwriting a locally defined method/ } @warnings,
    'no accessor-overwrite warning on load' );

# and the error accessor still works as a plain attribute
my $shotgun = App::Shotgun->new(
	file   => ['foo'],
	target => ['FTP:hostname=localhost'],
);
ok( ! defined $shotgun->error, 'error attribute defaults to undef' );

done_testing;
