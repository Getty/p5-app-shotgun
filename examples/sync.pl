use strict;
use warnings;

use App::Shotgun;

my $shotgun = App::Shotgun->new(
	source => '../',
	files => [
	      'examples/sync.pl',
	      'dist.ini',
	      'Changes',
	],
	targets => [
		{
			type => 'FTP',
			hostname => '192.168.0.55',
			username => 'apoc',
			password => 'apoc',
		},
	],
);

$shotgun->shot;

print "Success: ".($shotgun->success ? 'YES' : 'NO')."\n";
print "Error: ".$shotgun->error if (!$shotgun->success);
