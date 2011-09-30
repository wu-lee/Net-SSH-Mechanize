#!/usr/bin/perl 
use strict;
use warnings;
use Test::More tests => 3;
use FindBin qw($Bin);
use lib "$Bin/../local-lib/lib/perl5", "$Bin/../lib", "$Bin/lib";


use Net::SSH::Mechanize;
use MyTest::Mock::ConnectParams;

my $connection = MyTest::Mock::ConnectParams->detect;    

note "using command:";
note "    ", join " ", $connection->ssh_cmd;

my $ssh = Net::SSH::Mechanize->new(
    connection_params => $connection,
);


my $session = $ssh->login;

my @exchanges = (
    [q(id),
     qr/uid=\d+\(\S+\) gid=\d+\(\S+\)/],
    [q(printf "stdout output\n"; printf >&2 "stderr output\n" ),
     qr/\Astdout output\n\z/],
    [q(printf "eoled\nnot eoled"),
     qr/\Aeoled\nnot eoled\z/sm],
);

foreach my $exchange (@exchanges) {
    my ($cmd, $expect) = @$exchange;

    my $data = $session->sudo_capture($cmd);

    like $data, $expect, "$cmd: got expected data"
}

$session->logout;


