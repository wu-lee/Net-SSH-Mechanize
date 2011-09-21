package Net::SSH::Mechanize::ConnectParams;
use Moose;

has 'host' => (
    isa => 'Str',
    is => 'rw',
    required => 1,
);

has 'user' => (
    isa => 'Str',
    is => 'rw',
);

has 'port' => (
    isa => 'Int',
    is => 'rw',
    default => 22,
);

# has 'cmd' => (
#     isa => 'Str',
#     is => 'rw',
#     default => 'sh',
# );

# has 'has_pty' => (
#     isa => 'Bool',
#     is => 'rw',
#     default => 0,
# );


sub ssh_cmd {
    my $self = shift;

    my @cmd = ('-t', $self->host, 'sh');

    unshift @cmd, defined $self->user? ('-l', $self->user) : ();
    unshift @cmd, defined $self->port? ('-p', $self->port) : ();
    unshift @cmd, '/usr/bin/ssh';
    return @cmd;
}



__PACKAGE__->meta->make_immutable;
1;
