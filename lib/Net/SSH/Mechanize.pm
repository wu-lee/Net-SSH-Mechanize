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

use version; our $VERSION = qv('0.1');

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

__END__

=head1 NAME

Net::SSH::Mechanize - asynchronous ssh command invocation 

=head1 VERSION

This document describes Net::SSH::Mechanize version 0.1


=head1 SYNOPSIS

    use Net::SSH::Mechanize;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
Net::SSH::Mechanize requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-Net-SSH-Mechanize@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Nick Woolley  C<< <npw@cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, Nick Woolley C<< <npw@cpan.org> >>. All rights reserved.

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
