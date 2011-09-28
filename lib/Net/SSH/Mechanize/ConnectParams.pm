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

has 'password' => (
    isa => 'Str',
    is => 'rw',
    predicate => 'has_password',
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
__END__

=head1 NAME

Net::SSH::Mechanize::ConnectParams - encapsulates information about an ssh connection

=head1 VERSION

This document describes Net::SSH::Mechanize version 0.1

=head1 SYNOPSIS

This class is just a container for log-in details with a method which
constructs an approprate C<ssh> command invocation.

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
