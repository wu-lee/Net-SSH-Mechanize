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
__END__

=head1 NAME

Net::SSH::Mechanize::Multi - parallel ssh invocation 

=head1 VERSION

This document describes Net::SSH::Mechanize version 0.1

=head1 SYNOPSIS

Currently, the best example of this module's usage is in the gofer
script included in this distribution.

This documentation is unfinished.

=head1 AUTHOR

Nick Stokoe  C<< <npw@cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, Nick Stokoe C<< <npw@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
