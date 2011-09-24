package Net::SSH::Mechanize;
use AnyEvent;
#use AnyEvent::Log;
#use Coro;
use Moose;
use Net::SSH::Mechanize::ConnectParams;
use Net::SSH::Mechanize::Session;
use Net::SSH::Mechanize::Util;
use AnyEvent::Subprocess;
#use Scalar::Util qw(refaddr);
use Carp qw(croak);
our @CARP_NOT = qw(AnyEvent AnyEvent::Subprocess Coro::AnyEvent);
{ package Coro::AnyEvent; our @CARP_NOT = qw(AnyEvent::CondVar) }

#$AnyEvent::Log::FILTER->level("fatal");

=pod

use Log::Dispatch;
use Log::Dispatch::Screen;
my $logger = Log::Dispatch->new();
$logger->add(Log::Dispatch::Screen->new(
        name => 'screen',
        min_level => 'info',
        callbacks => sub {
            my %info = @_;
            return $info{message} . "\n";
        },
    ),
);

=cut

my @connection_params = qw(host user port);


has 'connection_params' => (
    isa => 'Net::SSH::Mechanize::ConnectParams',
    is => 'ro',
    handles => \@connection_params,
);


has '_subprocess_prototype' => (
    isa => 'AnyEvent::Subprocess',
    is => 'ro',
    default => sub {
        return AnyEvent::Subprocess->new(
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
#            on_error => sub { print "error! @_\n" },
#            on_completion => sub { printf "$Coro::current child complete!\n" },
            code  => sub { 
                my $args = shift;
                my $cp = $args->{params};
                exec $cp->ssh_cmd;
            },
        );
    },
);

around 'BUILDARGS' => sub {
    my $orig = shift;
    my $self = shift;

    my $params = $self->$orig(@_);

    # check for connection_params paramter
    if (exists $params->{connection_params}) {

        foreach my $param (@connection_params) {
            croak "Cannot specify both $param and connection_params parameters"
                if exists $params->{$param};
        }

        return $params; # as is
    }

    # Splice @connection_params out of %$params and into %cp_params
    my %cp_params;
    foreach my $param (@connection_params) {
        next unless exists $params->{$param};
        $cp_params{$param} = $params->{$param};
    }

    # Try and construct a ConnectParams instance
    my $cp = Net::SSH::Mechanize::ConnectParams->new(%cp_params);
    return {%$params, connection_params => $cp};
};


######################################################################
# public methods

sub login_async {
    my $self = shift;

    my $session;
#    $session = $self->_subprocess_prototype->run({
#        params => $self->connection_params,
#        on_completion => sub {
#            print "completing child PID ". $session->child_pid ."\n";
#            $session->_error_event->send("child PID ".$session->child_pid ." completed");
#            undefine $session;
#        },
#    });

    # We do this funny stuff with $session and $job so that the on_completion
    # callback can tell the session it should clean up
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
#            on_error => sub { print "error! @_\n" },
        on_completion => sub {
            printf "xx completing child PID %d _error_event %s is %s \n",
                $session->child_pid, $session->_error_event, $session->_error_event->ready? "ready":"unready";
            $session->_error_event->send("child PID ".$session->child_pid ." completed");
            undef $session;
        },
        code  => sub { 
            my $args = shift;
            my $cp = $args->{params};
            exec $cp->ssh_cmd;
        },
    );
    $session = $job->run({params => $self->connection_params});

    # turn off terminal echo
    $session->delegate('pty')->handle->fh->set_raw;

    # Rebless $session into a subclass of AnyEvent::Subprocess::Running
    # which just supplies extra methods we need.
#    bless $session, 'Net::SSH::Mechanize::Session';

printf "$Coro::current about to call login_async\n";
    my @arg = $session->login_async(@_);
    printf "$Coro::current exited login_async @arg\n";
    return @arg;
}

sub login {
#    return (shift->login_async(@_)->recv)[1];
    my ($cv) = shift->login_async(@_);
        printf "$Coro::current about to call recv\n";
    my $v = ($cv->recv)[1];
        printf "$Coro::current about to called recv\n";
    return $v;
}

__PACKAGE__->meta->make_immutable;
1;
