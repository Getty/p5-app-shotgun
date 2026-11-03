requires 'Expect', '1.21';
requires 'Log::Dispatch', '2.00';
requires 'Moose', '2.0007';
requires 'MooseX::Getopt', '0.37';
requires 'MooseX::LogDispatch', '1.2002';
requires 'MooseX::POE::SweetArgs', '0.213';
requires 'MooseX::Types::Path::Class', '0.05';
requires 'Net::Netrc';
requires 'Net::SFTP::Foreign', '1.64';
requires 'Path::Class', '0.23';
requires 'POE';
requires 'POE::Component::Client::SimpleFTP', '0.003';
requires 'POE::Component::Generic', '0.1205';

on test => sub {
    requires 'Test::More';
};
