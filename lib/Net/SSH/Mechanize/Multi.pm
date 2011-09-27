package Net::SSH::Mechanize::Multi;
use Moose;
use Net::SSH::Mechanize;
use Carp qw(croak);
use Coro;

######################################################################
# attributes

has 'ssh_instances' => (
    isa => 'ArrayRef[Net::SSH::Mechanize]',
    is => 'ro',
    default => sub { [] },
);


has 'names' => (
    isa => 'HashRef[Net::SSH::Mechanize]',
    is => 'ro',
    default => sub { +{} },
);

######################################################################

sub _to_ssh {
    my @instances;
    while(@_) {
        my ($name, $connection) = splice @_, 0, 2;
        $connection = Net::SSH::Mechanize::ConnectParams->new(%$connection)
            if ref $connection eq 'HASH';

        $connection = Net::SSH::Mechanize->new(connection_params => $connection)
            if blessed $connection 
                && $connection->isa('Net::SSH::Mechanize::ConnectParams');
        
        croak "Connection '$name' is not a hashref, Net::SSH::Mechanize::ConnectParams instance, nor a",
            "Net::SSH::Mechanize instance (it is $connection)"
                unless blessed $connection
                    && $connection->isa('Net::SSH::Mechanize');

        push @instances, $connection;
    }

    return @instances;
}


sub add {
    my $self = shift;
    croak "uneven number of name => connection parameters"
        if @_ % 2;

    my %new_instances = @_;

    my @new_names = keys %new_instances;
    my $names = $self->names;
    my @defined = grep { $names->{$_} } @new_names;

    croak "These names are already defined: @defined"
        if @defined;

    my @new_instances = _to_ssh %new_instances;
    
    my $instances = $self->ssh_instances;

    @$names{@new_names} = @new_instances;
    push @$instances, @new_instances;

    return @new_instances;
}


sub in_parallel {
    my $self = shift;
    my $cb = pop;
    croak "you must supply a callback"
        unless ref $cb eq 'CODE';
    
    my @names = @_;
    my $known_names = $self->names;
    my @instances = map { $known_names->{$_} } @names;
    if (@names != grep { defined } @instances) {
        my @unknown = grep { !$known_names->{$_} } @names;
        croak "These names are unknown: @unknown";
    }

    my @threads;
    my $ix = 0;

    foreach my $ix (0..$#instances) {
        push @threads, async {
            my $name = $names[$ix];
            my $ssh = $instances[$ix];
            
            eval {
                $cb->($name, $ssh);
                1;
            } or do {
                print "error ($name): $@";
            };
        }
    }

    return \@threads;
}



__PACKAGE__->meta->make_immutable;
1;
