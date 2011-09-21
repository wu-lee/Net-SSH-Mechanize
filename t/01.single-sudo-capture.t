#!/usr/bin/perl 
use strict;
use warnings;
use Test::More tests => 1;
use FindBin qw($Bin);
use lib "$Bin/../local-lib/lib/perl5", "$Bin/../lib";
use File::Slurp qw(slurp);


use Net::SSH::Mechanize;

my $ssh = Net::SSH::Mechanize->new(
    host => 'localhost',
);

my $passwd = slurp '../.passwd';
chomp $passwd;
my $session = $ssh->login($passwd);

my @exchanges = (
    [q(id),
     qr/uid=\d+\(\S+\) gid=\d+\(\S+\)/],
    [qq(ls $Bin/data/01.single-capture.t),
     qr/\Aa\s+b\s+c\s*\Z/sm],
    [q(perl -e 'print "eoled\nnot eoled"'),
     qr/\Aeoled\nnot eoled\Z/sm],
    [q(cat /etc/shadow | grep "^root:"),
     qr{^root:[^:]+:\d+:\d+:\d+}],
);

foreach my $exchange (@exchanges) {
    my ($cmd, $expect) = @$exchange;

    my $data = $session->sudo_capture($cmd, $passwd);

    like $data, $expect, "$cmd: got expected data"
}

$session->logout;


