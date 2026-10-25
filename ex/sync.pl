#!/usr/bin/perl
# execute in the app-shotgun root dir
#
# Replace the example hosts with your own. No login is given
# here: it is taken from ~/.netrc ( see the netrc support in App::Shotgun ).

use strict;
use warnings;

use App::Shotgun;

my $shotgun = App::Shotgun->new(
	source => '.',
	files => [
	      'examples/sync.pl',
	      'dist.ini',
	      'Changes',
	      'lib/App/Shotgun.pm',
	      'lib/App/Shotgun/Target/FTP.pm',
	],
	targets => [
		{
			type => 'FTP',
			path => '/1',
			hostname => 'ftp.example.com',
		},
		{
			type => 'FTP',
			path => '/2',
			hostname => 'ftp.example.com',
		},
		{
			type => 'FTP',
			path => '/3',
			hostname => 'ftp.example.com',
		},
		{
			type => 'SFTP',
			path => '/home/user/a',
			hostname => 'ftp.example.com',
		},
		{
			type => 'SFTP',
			path => '/home/user/b',
			hostname => 'ftp.example.com',
		},
		{
			type => 'SFTP',
			path => '/home/user/c',
			hostname => 'ftp.example.com',
		},
	],
);

$shotgun->shot;

print "Success: ".($shotgun->success ? 'YES' : 'NO')."\n";
print "Error: ".$shotgun->error if (!$shotgun->success);
