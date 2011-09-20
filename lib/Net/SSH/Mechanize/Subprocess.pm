package Net::SSH::Mechanize::Subprocess;
use Coro;
use AnyEvent::Subprocess;
use Net::SSH::Mechanize::Subprocess::Running;
use Moose;


extends 'AnyEvent::Subprocess';



override 'run' => sub {
    my $self = shift;

    my $subprocess = bless super(), 'Net::SSH::Mechanize::Subprocess::Running';

    # turn off terminal echo
    $subprocess->delegate('pty')->handle->fh->set_raw;

    return $subprocess;
};




######################################################################
# private methods

sub _ssh_invoker_cb {
    return sub {
        my $args = shift; #() + 1/0;
        defined $args->{host}
            or exit -1;# die "No host parameter supplied";
        my @cmd = ('-t', $args->{host}, 'sh');

        unshift @cmd, defined $args->{user}? ('-l', $args->{user}) : ();
        unshift @cmd, defined $args->{port}? ('-p', $args->{port}) : ();
        unshift @cmd, $args->{exe} || '/usr/bin/ssh';
        
        exec @cmd;
    };
}
######################################################################


sub default {
    my $class = shift;
    return $class->new(
        delegates => [
            'Pty', 
            'CompletionCondvar',
            'PrintError',
            [Handle => {
                name      => 'stderr',
                direction => 'r',
                replace   => \*STDERR,
            }],
        ],
        code  => $class->_ssh_invoker_cb, 
    );
}




__PACKAGE__->meta->make_immutable;
1;
