package App::Shotgun;
# ABSTRACT: mass upload of files via SCP/FTP/...

use MooseX::POE;
use Cwd;

with qw(
	MooseX::Getopt
);

has transferlog => (
	isa => 'Str',
	is => 'ro',
	predicate => 'has_transferlog',
);

has source => (
	isa => 'Str',
	is => 'ro',
	default => sub { getcwd },
);

has filelist => (
	isa => 'Str',
	is => 'ro',
	predicate => 'has_filelist',
);

has transfer_count => (
	traits  => ['Counter','NoGetopt'],
	is      => 'ro',
	isa     => 'Num',
	default => 0,
	handles => {
		inc_transfer_count => 'inc',
	},
);

has files => (
	traits  => ['Array'],
	is      => 'ro',
	isa     => 'ArrayRef[Str]',
	default => sub {
		my $self = shift;
		if ($self->has_filelist) {
			my @files;
			open (FILELIST, $self->filelist);
			while (my $file = <FILELIST>) {
				push @files, $file;
			}
			close(FILELIST);
			return \@files;
		}
		die "no files given";
	},
	handles => {
		all_files => 'elements',
		next_file => 'shift',
	},
);

has targets => (
	traits  => ['Array'],
	is      => 'ro',
	isa     => 'ArrayRef[HashRef[Str]]',
	required => 1,
);

sub BUILD {
	# make the target specification into: App::Shotgun::Target::$type objects in some internal var
}

sub shot {
	# DO IT!
}

1;

=head1 SYNOPSIS

  use App::Shotgun;
  
  my $shotgun = App::Shotgun->new(
    transferlog => 'transfer.log', # optional
    source => '../relative/path',
    files => [
      'robots.txt',
      'dir/dir/dir/file.txt',
      'category/index.html',
      'index.html',
    ],
    targets => [
      {
        name => 'Target 1', # optional
		dir => 'htdocs/', # optional
        type => 'FTP',
		# Type specific:
        hostname => 'my.local',
        username => 'notfor',
        password => 'you321',
      },
      {
        name => 'Target 2', # optional
        type => 'SCP',
		dir => '/tmp/testenv', # optional
		# Type specific:
        hostname => 'myother.local',
        username => 'notfor',
        # prepared key authentifications are just working
        # probably more options for configuring ssh, like alternative private key
      },
    ],
  );
  
  # Order of upload:
  # Target 1: robots.txt
  # Target 2: robots.txt
  # Target 1: dir/dir/dir/file.txt
  ä Target 2: dir/dir/dir/file.txt
  # ...
  
  $shotgun->shot;
  
  print "Transfer Count: ".$shotgun->transfer_count."\n";
  print "Success: ".($shotgun->success ? 'YES' : 'NO')."\n";
  print "Error: ".$shotgun->error if (!$shotgun-success);

  my $other_shotgun = App::Shotgun->new(
    source => '/absolute/path',
    filelist => 'filelist.txt',
  );

=head1 DESCRIPTION

This module uploads the filelist textfile given via B<filelist> or the filelist given as array via B<files> to all given B<targets>. It uploads file after file, to target after target, that means, first file will get uploaded to all target, and if they all are successful done, the next file will be uploaded.

For first the module is made to try again very often but will not continue on fail and close with an exit code above 0.

