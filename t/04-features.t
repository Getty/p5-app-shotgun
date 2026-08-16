#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec;
use File::Path qw( make_path );

use_ok( 'App::Shotgun' );

# minimal target stub exposing the bits the sync loop/logging touches
{
	package TargetStub;
	sub new  { my ( $class, %a ) = @_; bless \%a, $class }
	sub name { $_[0]->{name} }
}

# --- new attributes exist with sane defaults -------------------------------
{
	my $shotgun = App::Shotgun->new(
		file   => ['foo'],
		target => ['FTP:hostname=localhost'],
	);

	ok( ! $shotgun->has_transferlog, 'transferlog predicate false by default' );
	ok( ! $shotgun->parallel,         'parallel defaults to 0' );
	ok( ! $shotgun->filerecursive,    'filerecursive defaults to 0' );
}

# --- transferlog -----------------------------------------------------------
# The transferlog attribute should cause each completed transfer to be
# appended to the given file. _log_transfer is the hook the sync loop calls.
{
	my $dir = tempdir( CLEANUP => 1 );
	my $log = File::Spec->catfile( $dir, 'transfer.log' );

	my $shotgun = App::Shotgun->new(
		file        => ['foo'],
		target      => ['FTP:hostname=localhost'],
		transferlog => $log,
	);

	ok( $shotgun->has_transferlog, 'transferlog attribute is set' );

	my $target = bless { name => 'FTP::localhost' }, 'TargetStub';
	$shotgun->current_file( 'dir/file.txt' );
	$shotgun->_log_transfer( $target );

	open( my $fh, '<', $log ) or die "cannot read $log: $!";
	my $line = <$fh>;
	close( $fh );

	like( $line, qr/FTP::localhost/, 'transferlog contains the target name' );
	like( $line, qr/file\.txt/,     'transferlog contains the transferred file' );

	# without a transferlog, _log_transfer is a no-op
	my $silent = App::Shotgun->new(
		file   => ['foo'],
		target => ['FTP:hostname=localhost'],
	);
	$silent->current_file( 'x.txt' );
	is( $silent->_log_transfer( $target ), undef, '_log_transfer no-ops without transferlog' );
}

# --- recursive file list ---------------------------------------------------
# filerecursive should turn the source tree into a relative file list.
{
	my $dir = tempdir( CLEANUP => 1 );
	make_path( File::Spec->catdir( $dir, 'sub' ) );
	open( my $a, '>', File::Spec->catfile( $dir, 'a.txt' ) ) or die $!; close $a;
	open( my $b, '>', File::Spec->catfile( $dir, 'sub', 'b.txt' ) ) or die $!; close $b;

	my $shotgun = App::Shotgun->new(
		source        => $dir,
		filerecursive => 1,
		target        => ['FTP:hostname=localhost'],
	);

	my @files = sort @{ $shotgun->files };
	is_deeply( \@files, [ 'a.txt', File::Spec->catfile( 'sub', 'b.txt' ) ],
		'recursive file list is relative to source' );
}

# --- netrc support ---------------------------------------------------------
# _netrc_credentials maps a Net::Netrc machine's login/password (and the
# fallback to the default entry) into username/password params.
{
	package FakeNetrcMachine;
	sub new    { my ( $class, %a ) = @_; bless \%a, $class }
	sub login    { $_[0]->{login} }
	sub password { $_[0]->{password} }

	package main;

	my $shotgun = App::Shotgun->new(
		file   => ['foo'],
		target => ['FTP:hostname=localhost'],
	);

	# install one dispatch stub whose return value we swap between cases
	$NetrcMock::result = FakeNetrcMachine->new( login => 'me', password => 'secret' );
	{
		no warnings 'redefine', 'once';
		*Net::Netrc::lookup = sub { return $NetrcMock::result };
	}

	# login/password present for a matching host
	my $creds = $shotgun->_netrc_credentials('ftp.example.com');
	is_deeply( $creds, { username => 'me', password => 'secret' },
		'_netrc_credentials extracts login/password' );

	# machine found but no matching credentials
	$NetrcMock::result = FakeNetrcMachine->new();
	my $empty = $shotgun->_netrc_credentials('anyhost');
	is_deeply( $empty, {}, '_netrc_credentials tolerates missing login/password' );

	# no machine at all (including no default entry)
	$NetrcMock::result = undef;
	my $none = $shotgun->_netrc_credentials('anyhost');
	is_deeply( $none, {}, '_netrc_credentials handles undef machine' );

	# not consulted when there is no hostname
	$none = $shotgun->_netrc_credentials( undef );
	is_deeply( $none, {}, '_netrc_credentials handles undef hostname' );
}

# --- parallel --------------------------------------------------------------
{
	my $shotgun = App::Shotgun->new(
		file   => ['foo'],
		target => ['FTP:hostname=localhost'],
	);
	ok( ! $shotgun->parallel, 'parallel defaults to 0' );

	my $para = App::Shotgun->new(
		file     => ['foo'],
		target   => ['FTP:hostname=localhost'],
		parallel => 1,
	);
	ok( $para->parallel, 'parallel can be enabled' );
}

done_testing;
