#!/usr/bin/perl 
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/local-lib/lib/perl5", "$Bin/lib";
use File::Slurp qw(slurp);


use Net::SSH::Mechanize;

my $ssh = Net::SSH::Mechanize->new(
    host => 'aruna.interactive.co.uk',
);

my $passwd = slurp '.passwd';
chomp $passwd;
my $session = $ssh->login($passwd);

my @exchanges = (
    [q(id)],
    ['ls -lh'],
    [q(perl -e 'print "eoled\nnot eoled"')],
    [q(cat /etc/shadow | grep $USER)],
);

foreach my $exchange (@exchanges) {
    my ($cmd, $expect) = @$exchange;

    my $data = $session->capture($cmd);
    print "'$cmd' got:\n", $data;
}

foreach my $exchange (@exchanges) {
    my ($cmd, $expect) = @$exchange;

    my $data = $session->sudo_capture($cmd, $passwd);
    print "sudo '$cmd' got:\n", $data;
}

$session->logout;

__END__

to test
non-eol'ed output

broken input, possibly generating > continuation chars, i.e.

perl -e 'print "hello
there"'

