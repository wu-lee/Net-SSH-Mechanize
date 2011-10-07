package MyTest::Mock::ConnectParams;
use Moose;
extends 'Net::SSH::Mechanize::ConnectParams';

# Construct an instance of this class, unless env var TEST_PASSWD is defined,
# in whcih case construct a Net::SSH::Mechanize::ConnectParams instance.
sub detect {
    my $class = shift;

    return $class->new(host => 'nowhere',
                       password => 'sekrit')
        unless $ENV{TEST_PASSWD} || $ENV{TEST_HOST};

    return Net::SSH::Mechanize::ConnectParams->new(
        host => $ENV{TEST_HOST} || 'localhost',
        $ENV{TEST_PASSWD}? 
            (password => $ENV{TEST_PASSWD}) : (),
    );
}

sub ssh_cmd {
    return "$FindBin::Bin/bin/mock-ssh";
};

__PACKAGE__->meta->make_immutable;
1;
