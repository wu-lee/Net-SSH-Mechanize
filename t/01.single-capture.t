#!/usr/bin/perl 
use strict;
use warnings;
use Test::More tests => 5;
use FindBin qw($Bin);
use lib "$Bin/../local-lib/lib/perl5", "$Bin/../lib";
use File::Slurp qw(slurp);

use Net::SSH::Mechanize;

my $passwd = $ENV{PASSWD}
    or die "you must define the PASSWD environment variable";



my $ssh = Net::SSH::Mechanize->new(
    host => 'localhost',
);

my $session = $ssh->login($passwd);

my @exchanges = (
    [q(id),
     qr/uid=\d+\(\S+\) gid=\d+\(\S+\)/],
    [q(echo 'stdout output'; echo >&2 "stderr output" ),
     qr/\Astdout output\nstderr output\n\z/m],
    [qq(ls $Bin/data/01.single-capture.t),
     qr/\Aa\s+b\s+c\s*\z/sm],
    # using echo -ne instead of printf gets peculiar result: prints "-ne eoled\neoled"
    [q(printf "eoled\nnot eoled"),
     qr/\Aeoled\nnot eoled\z/m],
    [q(cat /etc/shadow | grep root),
     qr{cat: /etc/shadow: Permission denied}],
);

foreach my $exchange (@exchanges) {
    my ($cmd, $expect) = @$exchange;

    my $data = $session->capture($cmd);

    like $data, $expect, "$cmd: got expected data"
}

$session->logout;


