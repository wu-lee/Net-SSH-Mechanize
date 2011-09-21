package Net::SSH::Mechanize::Subprocess;
use Moose;

######################################################################
# attributes

# FIXME need to think about how to allow switching a pty subprocess for another.
# pty set_raw is currently hardwired in the factory class.

has 'ssh_process_factory' => (
    isa => 'Net::SSH::Mechanize::Subprocess',
    is => 'ro',
    lazy => 1,
    default => sub {
        return Net::SSH::Mechanize::Subprocess->default;
    },
);


has '_running_list' => (
    isa => 'HashRef',
    is => 'ro',
    default => sub { +{} },
);

######################################################################

sub add_session {
    my $self = shift;
    my %args = @_;

    # FIXME validate args here

    my $sessions = $self->sessions;

    push @$sessions, \%args;

    return $self;
}




sub login {
    my $self = shift;

    my $sessions = $self->sessions;
    my $running = $self->_running_list;
    my $count = 0;
    foreach my $session (@$sessions) {
        my $id = refaddr $session->{_pid};
        
        my $subprocess = $running->{$id};
        if ($subprocess) {
            my $pid = $subprocess->child_pid;
            warn "Session $id is already running with PID $pid, skipping it\n";
            next;
        }
        
        $running->{$id} = $self->spawn($session);
        $count++;
    }

    return $count;
}



sub capture {
    my $self = shift;
    my $cmd = shift;
    my $result_cb = shift;

    my $running = $self->_running_list;    
    my %results;
    foreach my $id (keys %$running) {

        my $coro = async {
            my $subprocess = $running->{$id};
            # FIXME check this gets a usable result

            my $pty = $subprocess->delegate('pty')->handle;
            
            sub logout {
                push_write "exit\n";
            }
        };
    }
    
}


__PACKAGE__->meta->make_immutable;
1;
