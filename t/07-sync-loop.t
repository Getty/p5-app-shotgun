#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use_ok( 'App::Shotgun' );

# A stub target stands in for a transport: it never touches the network. It
# answers the sync loop like a real one does - "ready" once connected, and
# "xferdone" when told to transfer. The events the loop yields to it are queued
# and played back by run_events, the way the POE kernel would.
{
	package StubTarget;

	our @LOG;     # global order of what happened: "name:file" per transfer
	our @QUEUE;   # events not yet delivered

	sub new {
		my ( $class, %a ) = @_;
		return bless { state => 'init', events => [], %a }, $class;
	}
	sub name  { $_[0]->{name} }
	sub state { my $s = shift; $s->{state} = shift if @_; $s->{state} }
	sub yield {
		my ( $self, $event ) = @_;
		push @{ $self->{events} }, $event;
		# a real transport is busy from the moment it is told to transfer; its
		# xferdone only comes after network round trips
		$self->state( 'xfer' ) if $event eq 'transfer';
		push @QUEUE, [ $self, $event ];
		return;
	}
	sub deliver {
		my ( $self, $event ) = @_;
		if ( $event eq 'transfer' ) {
			push @LOG, $self->name . ':' . $self->{shotgun}->current_file;
			$self->{shotgun}->_xferdone( $self );
		}
		return;
	}
}

sub run_events {
	while ( my $e = shift @StubTarget::QUEUE ) {
		$e->[0]->deliver( $e->[1] );
	}
}

sub build {
	my ( %args ) = @_;

	@StubTarget::LOG   = ();
	@StubTarget::QUEUE = ();

	my $shotgun = App::Shotgun->new(
		file   => [ qw( a b c ) ],
		target => ['FTP:hostname=localhost'],
		%args,
	);
	my @targets = map { StubTarget->new( name => $_, shotgun => $shotgun ) } qw( T1 T2 );
	$shotgun->new_connection( $_ ) for @targets;

	return ( $shotgun, @targets );
}

# --- serial: file after file, target after target --------------------------
{
	my ( $shotgun, $t1, $t2 ) = build();

	$shotgun->_ready( $t1 );
	is( scalar @StubTarget::QUEUE, 0, 'nothing is handed out while a target is still connecting' );
	is( $t1->state, 'ready', 'a ready target gets state ready' );

	$shotgun->_ready( $t2 );
	is( scalar @StubTarget::QUEUE, 1, 'the first file goes to one target only' );
	run_events();

	is_deeply(
		\@StubTarget::LOG,
		[ qw( T1:a T2:a T1:b T2:b T1:c T2:c ) ],
		'serial order: the first file reaches every target before the next file starts',
	);
	ok( $shotgun->success, 'success is set after the last file on the last target' );
	is_deeply( $t1->{events}, [ qw( transfer transfer transfer shutdown ) ], 'first target: three transfers, then shutdown' );
	is_deeply( $t2->{events}, [ qw( transfer transfer transfer shutdown ) ], 'second target: three transfers, then shutdown' );
	is( $shotgun->num_files, 0, 'the file list is used up' );
	is( $t1->state, 'ready', 'finished target is back in state ready' );
}

# --- parallel: all targets get the same file at once -----------------------
{
	my ( $shotgun, $t1, $t2 ) = build( parallel => 1 );

	$shotgun->_ready( $_ ) for $t1, $t2;
	is( scalar @StubTarget::QUEUE, 2, 'parallel: both targets get the first file at once' );
	is( $shotgun->current_file . '', 'a', 'parallel: current file is the first one' );
	run_events();

	is_deeply(
		[ sort @StubTarget::LOG[ 0, 1 ] ],
		[ qw( T1:a T2:a ) ],
		'parallel: both targets finish file a before file b starts',
	);
	is_deeply( [ sort @StubTarget::LOG[ 2, 3 ] ], [ qw( T1:b T2:b ) ], 'parallel: then file b on both' );
	is( scalar @StubTarget::LOG, 6, 'parallel: every file reached every target' );
	ok( $shotgun->success, 'parallel: success is set' );
}

# --- a single file, a single target -----------------------------------------
{
	my ( $shotgun, $t1 ) = build( file => ['only'] );
	pop @{ $shotgun->connections };

	$shotgun->_ready( $t1 );
	run_events();
	is_deeply( \@StubTarget::LOG, ['T1:only'], 'one file, one target: one transfer' );
	ok( $shotgun->success, 'one file, one target: success' );
}

# --- errors: the first one wins, every target is told to shut down ----------
{
	my ( $shotgun, $t1, $t2 ) = build();

	$shotgun->_error( 'first' );
	$shotgun->_error( 'second' );

	is( $shotgun->error, "first\n", 'only the first error is kept' );
	ok( ! $shotgun->success, 'an error leaves success unset' );
	is_deeply( $t1->{events}, ['shutdown'], 'first target is told to shut down once' );
	is_deeply( $t2->{events}, ['shutdown'], 'second target is told to shut down once' );
}

done_testing;
