package Net::SSH::Mechanize::Subprocess::Running;
use Moose;
use AnyEvent;
use Coro;
use Carp qw(croak);
use MIME::Base64 ();
extends 'AnyEvent::Subprocess::Running';

my $passwd_prompt_re = qr/:/;

my $initial_prompt_re = qr/^.*?\Q$ \E$/m;
# create a random text delimiter
my $delim = MIME::Base64::encode_base64 rand;
chomp $delim;

my $prompt_re = qr/$delim\Q$ \E$/m;


sub expect_async {
    my $self = shift;
    my $ready_cb = pop
        or croak "you must supplu a callback as the last argument";
    ref $ready_cb eq 'CODE'
        or croak "last argument is not a callback ($ready_cb)";
    
    $self->delegate('pty')->handle->push_read(@_, $ready_cb);    

#    print "expecting @_\n"; # DB

    return $self;
}


sub expect {
    my $self = shift;
    return $self->expect_async(@_, Coro::rouse_cb);
    my ($handle, $data) = Coro::rouse_wait;
    return $data;
}

sub push_write {
    my $self = shift;

#    print "writing @_\n"; # DB
    $self->delegate('pty')->handle->push_write(@_);
}

sub login_async {
    my $self = shift;
    my $ready_cb = pop
        or croak "you must supplu a callback as the last argument";
    ref $ready_cb eq 'CODE'
        or croak "last argument is not a callback ($ready_cb)";

    my $passwd = shift
        or croak "first argument must be a password.";

    $self->expect_async(regex => qr/$passwd_prompt_re|$initial_prompt_re/, sub {
        if ($_[1] =~ /$passwd_prompt_re/) { # we need to give the password
            $self->push_write("$passwd\n");
            $self->expect_async(regex => $initial_prompt_re, sub {
                $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

                $self->expect_async(regex => $prompt_re, sub {
                    $ready_cb->($_[0]);
                });
            });
        }
        else { # no password prompt
            $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

            $self->expect_async(regex => $prompt_re, sub {
                $ready_cb->($_[0]);
            });
        }
    });

    return $self;
}

sub login {
    my $self = shift;
    $self->login_async(@_, Coro::rouse_cb);
    Coro::rouse_wait;
    return $self;
}

sub logout {
    my $self = shift;
    $self->push_write("exit\n");
    return $self;
}



sub capture_async {
    my $self = shift;
    my $cmd = shift;
    my $ready_cb = pop
        or croak "you must supplu a callback as the last argument";
    ref $ready_cb eq 'CODE'
        or croak "last argument is not a callback ($ready_cb)";

    $cmd =~ s/\s*\Z/\n/ms;

    # send command
    $self->push_write($cmd);

    # read result
    my $cumdata = '';

    my $read_output_cb = sub {
        my ($handle) = @_;
        return unless defined $handle->{rbuf};
        
#        print "got: $handle->{rbuf}\n"; # DB
        
        $cumdata .= $handle->{rbuf};
        $handle->{rbuf} = '';
        
        $cumdata =~ /(.*?)$prompt_re/ms
            or return;

        $ready_cb->($handle, $1);
        return 1;
    };
    
    $self->delegate('pty')->handle->push_read($read_output_cb);
    
    return $self;
}


sub capture {
    my $self = shift;
    $self->capture_async(@_, Coro::rouse_cb);
    my ($handle, $data) = Coro::rouse_wait;
    return $data;
}



sub sudo_capture_async {
    my $self = shift;
    my $cmd = shift;
    my $passwd = shift;
    my $ready_cb = pop
        or croak "you must supplu a callback as the last argument";
    ref $ready_cb eq 'CODE'
        or croak "last argument is not a callback ($ready_cb)";

    # Erase any cached sudo authentication - we want to guarantee that
    # expect will negotiate a password prompt.
    $self->push_write("sudo -K\n");

    # Now authenticate using sudo
    my $passwd_prompt = "$delim-passwd:";
    $self->push_write("sudo -p $passwd_prompt sh\n");
    $self->expect_async(regex => qr/$passwd_prompt$/sm, sub {
        $self->push_write("$passwd\n");
        $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

        $self->expect_async(regex => $prompt_re, sub {
            $self->capture_async($cmd, sub {
                 my ($handle, $data) = @_;

                 $self->logout;
                 $self->expect_async(regex => $prompt_re, sub {
                     my $handle = shift;
                     $ready_cb->($handle, $data);
                 });
            });
        });
    });

    return $self;
}

sub sudo_capture {
    my $self = shift;
    $self->sudo_capture_async(@_, Coro::rouse_cb);
    my ($handle, $data) = Coro::rouse_wait;
    return $data;
}


__PACKAGE__->meta->make_immutable;
1;
