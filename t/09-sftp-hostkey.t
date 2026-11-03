#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec;
use JSON::PP qw( encode_json decode_json );
use POE::Kernel;

use_ok( 'App::Shotgun' );
use_ok( 'App::Shotgun::Target::SFTP' );

# --- an unknown host key is an error within seconds, never a hang -----------
# ( first: the shot runs in a forked process that must not inherit POE sessions )
my $env = $ENV{SHOTGUN_TEST_SFTP};
SKIP: {
	skip 'set SHOTGUN_TEST_SFTP to test against a real server', 4 if ! defined $env || ! length $env;

	my( $host, $port, $user, $pass, $base ) = split( /:/, $env, 5 );
	$base = '/' if ! defined $base || ! length $base;

	# a known_hosts without the key of the server: the key is unknown
	my $empty = File::Spec->catfile( tempdir( CLEANUP => 1 ), 'known_hosts' );
	open( my $fh, '>', $empty ) or die "cannot write $empty: $!";
	close( $fh ) or die "cannot close $empty: $!";

	pipe( my $r, my $w ) or die "pipe: $!";
	my $pid = fork;
	die "fork: $!" if ! defined $pid;
	if ( ! $pid ) {
		close( $r );
		alarm 30;
		my $started = time;
		my $shotgun = App::Shotgun->new(
			source  => '/etc',
			files   => ['hostname'],
			targets => [ {
				type => 'SFTP', hostname => $host, port => $port, username => $user, password => $pass,
				path => $base, ssh_options => [ "UserKnownHostsFile=$empty" ],
			} ],
			logger  => Log::Dispatch->new( outputs => [ [ 'Null', min_level => 'debug' ] ] ),
		);
		eval { $shotgun->shot; 1 } or $shotgun->error( "died: $@" );
		print {$w} encode_json( { success => $shotgun->success ? 1 : 0, error => $shotgun->error, seconds => time - $started } );
		close( $w );
		exit 0;
	}
	close( $w );
	my $json = do { local $/; <$r> };
	waitpid( $pid, 0 );
	my $res = decode_json( $json || '{"error":"no result - the shot did not end"}' );

	ok( ! $res->{success}, 'an unknown host key is not a success' );
	like( $res->{error} || '', qr/CONNECT error/, 'it ends as a connect error' );
	like( $res->{error} || '', qr/known_hosts.*\Q$host:$port\E.*ssh_options/, 'the message names the host and where to look' );
	cmp_ok( $res->{seconds} // 99, '<', 15, 'it ends within seconds' );
}

# --- the ssh options a target is built with, no server needed ---------------
{
	my $shotgun = App::Shotgun->new(
		file   => ['foo'],
		target => ['FTP:hostname=localhost'],
	);
	my $new = sub {
		App::Shotgun::Target::SFTP->new( hostname => 'localhost', username => 'u', shotgun => $shotgun, @_ );
	};

	is_deeply( $new->()->_ssh_more, [ qw( -o StrictHostKeyChecking=yes -o BatchMode=yes ) ],
		'key login: strict host key checking and batch mode by default' );

	is_deeply( $new->( password => 'p' )->_ssh_more, [ qw( -o StrictHostKeyChecking=yes ) ],
		'password login: strict host key checking, no batch mode ( it would stop the password )' );

	is_deeply(
		$new->( password => 'p', ssh_options => ['StrictHostKeyChecking=accept-new', 'UserKnownHostsFile=/x'] )->_ssh_more,
		[ qw( -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/x -o StrictHostKeyChecking=yes ) ],
		'ssh_options come first, ssh takes the first value of an option',
	);

	is_deeply( $new->( password => 'p', ssh_options => 'A=1,B=2' )->_ssh_more,
		[ qw( -o A=1 -o B=2 -o StrictHostKeyChecking=yes ) ],
		'ssh_options given as a comma separated string' );

	# a target string from the command line
	my $cli = App::Shotgun->new(
		file   => ['foo'],
		target => ['SFTP:hostname=localhost:username=u:ssh_options=UserKnownHostsFile=/x,LogLevel=ERROR'],
	);
	is( $cli->targets->[0]{ssh_options}, 'UserKnownHostsFile=/x,LogLevel=ERROR', 'ssh_options survives the target string' );
}

# the objects above started POE sessions that never run: drop them quietly
POE::Kernel->stop;

done_testing;
