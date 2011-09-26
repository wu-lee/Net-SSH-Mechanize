#!/usr/bin/perl 
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../local-lib/lib/perl5", "$Bin/../lib";
use File::Slurp qw(slurp);
use Coro;

use Net::SSH::Mechanize;
use Coro::Debug;


my $passwd = $ENV{PASSWD}
    or die "you must define the PASSWD environment variable";


my $threads = 10;

my @exchanges = (
    [q(id),
     qr/uid=\d+\(\S+\) gid=\d+\(\S+\)/],
    [qq(ls $Bin/data/01.single-capture.t),
     qr/\Aa\s+b\s+c\s*\z/sm],
    [q(printf "eoled\nnot eoled"),
     qr/\Aeoled\nnot eoled\z/sm],
    [q(cat /etc/shadow | grep root),
     qr{cat: /etc/shadow: Permission denied}],
);

plan tests => @exchanges * $threads + 2;

my %connection = (
    host => 'localhost',
#    host => 'aruna.interactive.co.uk',
#    host => 'auriga',
);
my (@ssh) = map { Net::SSH::Mechanize->new(%connection) } 1..$threads;
is @ssh, $threads, "number of subprocesses is $threads";

my @threads;
my $ix = 0;
foreach my $ix (1..@ssh) {
    push @threads, async {
        my $id = $ix;
        my $ssh = $ssh[$id-1];
        note "(thread=$ix) starting";
            $id == 11 and Coro::Debug::trace;
        eval {
            my $session = $ssh->login($passwd);
            note "(thread=$ix) logged in";  
            foreach my $exchange (@exchanges) {
                my ($cmd, $expect) = @$exchange;
                
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

is @threads, $threads, "number of threads is $threads";
my $id = 0;
foreach my $thread (@threads) {
    note "joining thread ",++$id;
    $thread->join;
}
        
