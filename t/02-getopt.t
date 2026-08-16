#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use_ok( 'App::Shotgun' );

# bin/shotgun depends on MooseX::Getopt's new_with_options being composed
# into App::Shotgun. A future refactor that replaces the role composition
# with a plain `use MooseX::Getopt;` silently breaks the CLI. Guard
# against it here.
can_ok( 'App::Shotgun', 'new_with_options' );

done_testing;
