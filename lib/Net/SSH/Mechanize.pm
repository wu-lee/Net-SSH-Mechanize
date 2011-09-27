package Net::SSH::Mechanize;
use AnyEvent;
#use AnyEvent::Log;
#use Coro;
use Moose;
use Net::SSH::Mechanize::ConnectParams;
use Net::SSH::Mechanize::Session;
use AnyEvent::Subprocess;
#use Scalar::Util qw(refaddr);
use Carp qw(croak);
our @CARP_NOT = qw(AnyEvent AnyEvent::Subprocess Coro::AnyEvent);

{
    # Stop our carp errors from being reported within AnyEvent::Coro
    package Coro::AnyEvent;
    our @CARP_NOT = qw(AnyEvent::CondVar);
}

#$AnyEvent::Log::FILTER->level("fatal");


my @connection_params = qw(host user port password);


has 'connection_params' => (
    isa => 'Net::SSH::Mechanize::ConnectParams',
    is => 'ro',
    handles => \@connection_params,
);


has 'session' => (
    isa => 'Net::SSH::Mechanize::Session',
    is => 'ro',
    lazy => 1,
    default => sub {
        shift->login;
    },
    handles => [qw(capture capture_async sudo_capture sudo_capture_async logout)],
);


around 'BUILDARGS' => sub {
    my $orig = shift;
    my $self = shift;

    my $params = $self->$orig(@_);

    # check for connection_params paramter
    my $cp;
    if (exists $params->{connection_params}) {
        # Prevent duplication of parameters - if we have a connection_params
        # parameter, forbid the shortcut alternatives.
        foreach my $param (@connection_params) {
            croak "Cannot specify both $param and connection_params parameters"
                if exists $params->{$param};
        }

        $cp = $params->{connection_params};
        $cp = Net::SSH::Mechanize::ConnectParams->new($cp)
                if ref $cp eq 'HASH';
    }
    else {
        # Splice the short-cut @connection_params out of %$params and into %cp_params
        my %cp_params;
        foreach my $param (@connection_params) {
            next unless exists $params->{$param};
            $cp_params{$param} = delete $params->{$param};
        }

        # Try and construct a ConnectParams instance
        $cp = Net::SSH::Mechanize::ConnectParams->new(%cp_params);
    }

    return {
        %$params, 
        connection_params => $cp,
    };
};


######################################################################
# public methods

sub login_async {
    my $self = shift;

    # We do this funny stuff with $session and $job so that the on_completion
    # callback can tell the session it should clean up
    my $session;
    my $job = AnyEvent::Subprocess->new(
        run_class => 'Net::SSH::Mechanize::Session',
        delegates => [
            'Pty', 
            'CompletionCondvar',
            [Handle => {
                name      => 'stderr',
                direction => 'r',
                replace   => \*STDERR,
            }],
        ],
        on_completion => sub {
            my $done = shift;
            
#            printf "xx completing child PID %d _error_event %s is %s \n",
#                $session->child_pid, $session->_error_event, $session->_error_event->ready? "ready":"unready"; #DB
            my $stderr = $done->delegate('stderr');
            my $errtext = $stderr->rbuf;
            my $msg = sprintf "child PID %d terminated unexpectedly with exit value %d",
                $session->child_pid, $done->exit_value, $errtext? "\n$errtext" : '';
            $session->_error_event->send($msg);
            undef $session;
        },
        code  => sub { 
            my $cmd = shift->{cmd};
            exec @$cmd;
        },
    );
    $session = $job->run({cmd => [$self->connection_params->ssh_cmd]});
    
    # Tack this on afterwards, mainly to supply the password.  We
    # can't add it to the constructor above because of the design of
    # AnyEvent::Subprocess.
    $session->connection_params($self->connection_params);

    # turn off terminal echo
    $session->delegate('pty')->handle->fh->set_raw;

    # Rebless $session into a subclass of AnyEvent::Subprocess::Running
    # which just supplies extra methods we need.
#    bless $session, 'Net::SSH::Mechanize::Session';

    #printf "$Coro::current about to call login_async\n"; DB coro
    my @arg = $session->login_async(@_);
    # printf "$Coro::current exited login_async @arg\n"; # DB coro
    return @arg;
}

sub login {
#    return (shift->login_async(@_)->recv)[1];
    my ($cv) = shift->login_async(@_);
#        printf "$Coro::current about to call recv\n"; # DB 
    my $v = ($cv->recv)[1];
#        printf "$Coro::current about to called recv\n"; # DB 
    return $v;
}

__PACKAGE__->meta->make_immutable;
1;
