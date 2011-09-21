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

    my $session = $self->_subprocess_prototype->run({params => $self->connection_params});

    # turn off terminal echo
    $session->delegate('pty')->handle->fh->set_raw;

    # Rebless $session into a subclass of AnyEvent::Subprocess::Running
    # which just supplies extra methods we need.
    bless $session, 'Net::SSH::Mechanize::Session';


    return $session->login_async(@_);
}

sub login {
    return Net::SSH::Mechanize::Util->synchronize(shift, login_async => @_);
}

__PACKAGE__->meta->make_immutable;
1;
