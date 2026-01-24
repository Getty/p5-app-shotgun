requires 'Moose', '2.0007';
requires 'MooseX::Types::Path::Class', '0.05';
requires 'Path::Class', '0.23';
requires 'MooseX::Getopt', '0.37';
requires 'MooseX::LogDispatch', '1.2002';
requires 'POE::Component::Client::SimpleFTP', '0.003';
requires 'POE::Component::Generic', '0.1205';
requires 'MooseX::POE::SweetArgs', '0.213';
requires 'Net::SFTP::Foreign', '1.64';
requires 'Expect', '1.21';

on test => sub {
    requires 'Test::More';
};
