#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec;
use File::Path qw( make_path );
use JSON::PP qw( encode_json decode_json );

# Walks the target state machine ( init -> ready -> testdir -> dir -> xfer )
# of the FTP and the SFTP transport against a real server. Skipped without a
# server:
#
#   SHOTGUN_TEST_FTP=host:port:user:pass:basepath
#   SHOTGUN_TEST_SFTP=host:port:user:pass:basepath
#
# basepath must exist and be writable for the user; the test works in a fresh
# subdirectory of it and removes that again. A colon cannot be part of the
# password.

my %server;
for my $type ( qw( FTP SFTP ) ) {
	my $env = $ENV{"SHOTGUN_TEST_$type"};
	next if ! defined $env || ! length $env;
	my( $host, $port, $user, $pass, $base ) = split( /:/, $env, 5 );
	$base = '/' if ! defined $base || ! length $base;
	$base =~ s{(?<=.)/+$}{};
	$server{$type} = { host => $host, port => $port, user => $user, pass => $pass, base => $base };
}

plan skip_all => 'set SHOTGUN_TEST_FTP and/or SHOTGUN_TEST_SFTP to test against a real server'
	if ! %server;

use_ok( 'App::Shotgun' );

# The SFTP transport hands no ssh options to Net::SFTP::Foreign, and a throwaway
# test server has a host key nobody knows: ssh would wait for an answer that
# never comes. A wrapper first in the PATH switches the host key check off for
# this test only, without touching the ~/.ssh of the user.
if ( $server{SFTP} ) {
	my( $ssh ) = grep { -x $_ } map { "$_/ssh" } split( /:/, $ENV{PATH} );
	if ( $ssh ) {
		my $bin = tempdir( CLEANUP => 1 );
		my $wrapper = "$bin/ssh";
		open( my $fh, '>', $wrapper ) or die "cannot write $wrapper: $!";
		print {$fh} "#!/bin/sh\nexec $ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \"\$@\"\n";
		close( $fh ) or die "cannot close $wrapper: $!";
		chmod 0755, $wrapper or die "cannot chmod $wrapper: $!";
		$ENV{PATH} = "$bin:$ENV{PATH}";
	} else {
		diag( 'no ssh in the PATH, SFTP is not tested' );
		delete $server{SFTP};
	}
}

# a nested tree, so the directories have to be created level by level
my %content = (
	'top.txt'       => "top\n",
	'd1/one.txt'    => "one\n" x 3,
	'd1/d2/two.txt' => "two\n" x 5000, # more than one 10240 byte chunk
);
my @files = sort keys %content;

my $source = tempdir( CLEANUP => 1 );

sub write_tree {
	my $leaf = shift;

	for my $f ( @files ) {
		my @parts = ( $leaf, split( m{/}, $f ) );
		my $name  = pop @parts;
		my $dir   = File::Spec->catdir( $source, @parts );
		make_path( $dir );
		my $path = File::Spec->catfile( $dir, $name );
		open( my $fh, '>', $path ) or die "cannot write $path: $!";
		binmode( $fh );
		print {$fh} $content{$f};
		close( $fh ) or die "cannot close $path: $!";
	}

	return;
}

# --- the remote side, to look at what arrived and to clean up ---------------
sub remote {
	my( $type, $s ) = @_;

	if ( $type eq 'FTP' ) {
		require Net::FTP;
		my $ftp = Net::FTP->new( $s->{host}, Port => $s->{port}, Passive => 1, Timeout => 30 )
			or die "FTP connect: $@";
		$ftp->login( $s->{user}, $s->{pass} ) or die "FTP login: " . $ftp->message;
		$ftp->binary;
		return {
			get => sub {
				my $path = shift;
				my $buf = '';
				open( my $fh, '>', \$buf ) or die $!;
				my $ok = $ftp->get( $path, $fh );
				close( $fh );
				return $ok ? $buf : undef;
			},
			rm_tree => sub { _ftp_rm_tree( $ftp, shift ) },
		};
	}

	require Net::SFTP::Foreign;
	my $sftp = Net::SFTP::Foreign->new(
		host => $s->{host}, port => $s->{port}, user => $s->{user}, password => $s->{pass},
		timeout => 30,
	);
	die "SFTP connect: " . $sftp->error if $sftp->error;
	return {
		get     => sub { scalar $sftp->get_content( shift ) },
		rm_tree => sub { $sftp->rremove( shift ) },
	};
}

sub _ftp_rm_tree {
	my( $ftp, $dir ) = @_;

	for my $entry ( $ftp->ls( $dir ) ) {
		my $p = $entry =~ m{^/} ? $entry : "$dir/$entry";
		next if $p =~ m{/\.\.?$};
		defined $ftp->size( $p ) ? $ftp->delete( $p ) : _ftp_rm_tree( $ftp, $p );
	}
	$ftp->rmdir( $dir );

	return;
}

# --- one shot, in its own process: the POE kernel runs once per process -----
sub shoot {
	my( $type, $s, $path, $files ) = @_;

	pipe( my $r, my $w ) or die "pipe: $!";
	my $pid = fork;
	die "fork: $!" if ! defined $pid;

	if ( ! $pid ) {
		close( $r );
		alarm 90; # a stuck transport must fail the test, not hang it
		my $shotgun = App::Shotgun->new(
			source  => $source,
			files   => $files,
			targets => [ {
				type => $type, hostname => $s->{host}, port => $s->{port},
				username => $s->{user}, password => $s->{pass}, path => $path,
			} ],
			logger  => Log::Dispatch->new( outputs => [ [ 'Null', min_level => 'debug' ] ] ),
		);
		eval { $shotgun->shot; 1 } or $shotgun->error( "died: $@" );
		my $c = $shotgun->connections->[0];
		print {$w} encode_json( {
			success => $shotgun->success ? 1 : 0,
			error   => $shotgun->error,
			state   => $c ? $c->state : undef,
			known   => $c ? [ sort keys %{ $c->_knowndirs } ] : [],
		} );
		close( $w );
		exit 0;
	}

	close( $w );
	my $json = do { local $/; <$r> };
	waitpid( $pid, 0 );

	return decode_json( $json || '{"error":"no result from the shot process"}' );
}

for my $type ( sort keys %server ) {
	my $s      = $server{$type};
	my $leaf   = "shotgun-t-$$-" . time . "-" . lc $type;
	my $remote = remote( $type, $s );
	my @shot   = map { "$leaf/$_" } @files;
	write_tree( $leaf );

	# 1. a target path that does not exist: state init ends in an error, no hang
	{
		my $res = shoot( $type, $s, "$s->{base}/$leaf-missing/deeper", \@shot );
		ok( ! $res->{success}, "$type: a missing target path is not a success" );
		like( $res->{error} || '', qr/initial path/, "$type: the missing target path is reported from state init" );
		is( $res->{state}, 'init', "$type: the target never left state init" );
	}

	# 2. fresh tree: testdir fails, dir creates level by level, xfer follows
	{
		my $res = shoot( $type, $s, $s->{base}, \@shot );
		ok( $res->{success}, "$type: the first run succeeds" ) or diag( $res->{error} );
		ok( ! defined $res->{error}, "$type: the first run has no error" );
		is( $res->{state}, 'ready', "$type: the target ends in state ready" );
		for my $f ( @files ) {
			is( $remote->{get}->( "$s->{base}/$leaf/$f" ), $content{$f}, "$type: $f arrived complete" );
		}
		my $full = File::Spec->catdir( $s->{base}, $leaf, 'd1', 'd2' );
		ok( ( grep { $_ eq $full } @{ $res->{known} } ), "$type: the created directories are in the known dirs" );
	}

	# 3. again: every file is sent again, the existing directories are only entered
	{
		my $res = shoot( $type, $s, $s->{base}, \@shot );
		ok( $res->{success}, "$type: the second run succeeds" ) or diag( $res->{error} );
		for my $f ( @files ) {
			is( $remote->{get}->( "$s->{base}/$leaf/$f" ), $content{$f}, "$type: $f is complete after the second run" );
		}
	}

	eval { $remote->{rm_tree}->( "$s->{base}/$leaf" ) };
}

done_testing;
