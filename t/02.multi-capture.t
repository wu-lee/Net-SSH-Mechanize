#!/usr/bin/perl 
use strict;
use warnings;
use Test::More tests => 1;
use FindBin qw($Bin);
use lib "$Bin/../local-lib/lib/perl5", "$Bin/../lib";
use File::Slurp qw(slurp);
use Coro;

use Net::SSH::Mechanize;
use Coro::Debug;

 our $server = new_unix_server Coro::Debug "/tmp/socketpath";


my $passwd = slurp '../.passwd';
chomp $passwd;


my $max = 11;

my @exchanges = (
    [q(id),
     qr/uid=\d+\(\S+\) gid=\d+\(\S+\)/],
    [qq(ls $Bin/data/01.single-capture.t),
     qr/\Aa\s+b\s+c\s*\Z/sm],
    [q(perl -e 'print "eoled\nnot eoled"'),
     qr/\Aeoled\nnot eoled\Z/sm],
    [q(cat /etc/shadow | grep root),
     qr{cat: /etc/shadow: Permission denied}],
);

use Coro::Debug;

my %connection = (
    host => 'localhost',
#    host => 'aruna.interactive.co.uk',
#    host => 'auriga',
);
my (@ssh) = map { Net::SSH::Mechanize->new(%connection) } 1..$max;
is @ssh, $max, "number of subprocesses is $max";

my @threads;
my $ix = 0;
foreach my $ix (1..@ssh) {
    push @threads, async {
        my $id = $ix;
        my $ssh = $ssh[$id-1];
        note "(thread=$ix $Coro::current) starting";
            $id == 11 and Coro::Debug::trace;
        eval {
            my $session = $ssh->login($passwd);
            note "(thread=$ix) logged in";  
            foreach my $exchange (@exchanges) {
                my ($cmd, $expect) = @$exchange;
                
                next;
                my $data = $session->capture($cmd);
                
                like $data, $expect, "(thread=$ix) $cmd: got expected data";
            }
            
            $session->logout;
            note "(thread=$ix) logged out";           
            1;
        } or do {
            note "(thread=$ix) error: $@";
        };
        note "(thread=$ix) ending";
     };
}

is @threads, $max, "number of threads is $max";
my $id = 0;
foreach my $thread (@threads) {
    note "joining thread ",++$id;
    $thread->join;
}
        
