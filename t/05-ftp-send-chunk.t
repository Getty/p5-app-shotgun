#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec;

use_ok( 'App::Shotgun::Target::FTP' );

# send_chunk only touches a handful of methods, so a stub is enough: no
# server, no POE session.
{
	package ChunkStub;
	sub new     { my ( $class, %a ) = @_; bless { %a, calls => [], errors => [] }, $class }
	sub name    { 'FTP::stub' }
	sub file    { Path::Class::File->new( $_[0]->{file} ) }
	sub shotgun { $_[0] }
	sub source  { $_[0]->{source} }
	sub _filefh { $_[0]->{fh} }
	sub ftp     { my $s = shift; push @{ $s->{calls} }, [ @_ ]; return }
	sub error   { my $s = shift; push @{ $s->{errors} }, @_; return }
}

my $dir = tempdir( CLEANUP => 1 );

# --- a failing read is an error, never a finished upload -------------------
{
	# a directory opens fine for reading, but read() on it fails with EISDIR
	my $broken = File::Spec->catdir( $dir, 'broken' );
	mkdir $broken or die "mkdir $broken: $!";
	open( my $fh, '<', $broken ) or die "open $broken: $!";

	my $stub = ChunkStub->new( file => 'broken', source => $dir, fh => $fh );
	App::Shotgun::Target::FTP::send_chunk( $stub );

	is( scalar @{ $stub->{errors} }, 1, 'failed read reports one error' );
	like( $stub->{errors}[0], qr/unable to read/, 'error names the read failure' );
	ok( ! ( grep { $_->[0] eq 'put_close' } @{ $stub->{calls} } ), 'failed read does not close the upload' );
	ok( ! @{ $stub->{calls} }, 'failed read sends nothing to the server' );
}

# --- the regular path still works ------------------------------------------
{
	my $file = File::Spec->catfile( $dir, 'good.txt' );
	open( my $out, '>', $file ) or die "open $file: $!";
	print {$out} 'hello';
	close( $out );
	open( my $fh, '<', $file ) or die "open $file: $!";

	my $stub = ChunkStub->new( file => 'good.txt', source => $dir, fh => $fh );

	App::Shotgun::Target::FTP::send_chunk( $stub );
	is_deeply( $stub->{calls}, [ [ 'put_data', 'hello' ] ], 'data chunk is sent' );

	App::Shotgun::Target::FTP::send_chunk( $stub );
	is( $stub->{calls}[1][0], 'put_close', 'end of file closes the upload' );
	ok( ! @{ $stub->{errors} }, 'regular upload reports no error' );
}

done_testing;
