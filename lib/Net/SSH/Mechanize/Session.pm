package Net::SSH::Mechanize::Session;
use Moose;
use MooseX::Params::Validate;
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
    my ($ready_cb) = pos_validated_list(
        [pop @_],
        { isa => 'CodeRef' },
    );

    $self->delegate('pty')->handle->push_read(@_, $ready_cb);    

#    print "expecting @_\n"; # DB

    return $self;
}


sub expect {
    return Net::SSH::Mechanize::Util->synchronize(shift, expect_async => @_);
}

sub push_write {
    my $self = shift;

#    print "writing @_\n"; # DB
    $self->delegate('pty')->handle->push_write(@_);
}

sub login_async {
    my $self = shift;
    my ($passwd, $ready_cb) = pos_validated_list(
        \@_,
        { isa => 'Str' },
        { isa => 'CodeRef' },
    );

    $self->expect_async(regex => qr/$passwd_prompt_re|$initial_prompt_re/, sub {
        if ($_[1] =~ /$passwd_prompt_re/) { # we need to give the password
            $self->push_write("$passwd\n");
            $self->expect_async(regex => $initial_prompt_re, sub {
                $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

                $self->expect_async(regex => $prompt_re, sub {
                    $ready_cb->($_[0], $self);
                });
            });
        }
        else { # no password prompt
            $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

            $self->expect_async(regex => $prompt_re, sub {
                $ready_cb->($_[0], $self);
            });
        }
    });

    return $self;
}

sub login {
    return Net::SSH::Mechanize::Util->synchronize(shift, login_async => @_);
}


sub logout {
    my $self = shift;
    $self->push_write("exit\n");
    return $self;
}



sub capture_async {
    my $self = shift;
    my ($cmd, $ready_cb) = pos_validated_list(
        \@_,
        { isa => 'Str' },
        { isa => 'CodeRef' },
    );

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
    return Net::SSH::Mechanize::Util->synchronize(shift, capture_async => @_);
}


sub sudo_capture_async {
    my $self = shift;
    my ($cmd, $passwd, $ready_cb) = pos_validated_list(
        \@_,
        { isa => 'Str' },
        { isa => 'Str' },
        { isa => 'CodeRef' },
    );

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
    return Net::SSH::Mechanize::Util->synchronize(shift, sudo_capture_async => @_);
}


__PACKAGE__->meta->make_immutable;
1;
