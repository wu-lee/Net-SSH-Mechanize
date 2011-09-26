package Net::SSH::Mechanize::Session;
use Moose;
use MooseX::Params::Validate;
use AnyEvent;
use Carp qw(croak);
use MIME::Base64 ();
our @CARP_NOT = qw(Net::SSH::Mechanize AnyEvent);

extends 'AnyEvent::Subprocess::Running';

my $passwd_prompt_re = qr/:\s*/;

my $initial_prompt_re = qr/^.*?\Q$ \E$/m;
my $sudo_initial_prompt_re = qr/^.*?\Q$ \E$/m;

# create a random text delimiter
my $delim = MIME::Base64::encode_base64 rand;
chomp $delim;
my $prompt = "$delim";

my $sudo_passwd_prompt = "$delim-passwd";

my $prompt_re = qr/\Q$prompt\E$/sm;

my $sudo_passwd_prompt_re = qr/^$sudo_passwd_prompt$/;


my $login_timeout_secs = 10;

has '_error_event' => (
    is => 'rw',
    isa => 'AnyEvent::CondVar',
    default => sub { return AnyEvent->condvar },
);

sub _push_write {
    my $handle = shift;

#    print qq(writing: "@_"\n); # DB
    $handle->push_write(@_);
}


# helper function
sub _match {
    my $handle = shift;
    my $re = shift;
    return unless $handle->{rbuf};
    my @captures = $handle->{rbuf} =~ /$re/;
    if (!@captures) {
#        print qq(not matching $re: "$handle->{rbuf}"\n); # DB    
        return;
    }

#    print qq(matching $re with: "$handle->{rbuf}"\n); # DB

    substr $handle->{rbuf}, 0, $+[0], "";
    return @captures;
}

sub _define_automation {
    my $self = shift;
    my $states = {@_};
    my $function = (caller 1)[3];
    
    my ($stdin, $stderr) = map { $self->delegate($_)->handle } qw(pty stderr);

    my $state = 'start';
    my $cb;
    $cb = sub {
#        printf "before: state is %s %s\n", $function, $state; # DB 
        $state = $states->{$state}->(@_);
        exists $states->{$state}
            or die "something is wrong, next state returned is undefined ($state)";

#        printf "after: state is %s %s\n", $function, $state; # DB 
        if (!$states->{$state}) { # terminal state, stop reading
#            $stderr->on_read(); # cancel errors on stderr
            $stdin->{rbuf} = '';
            return 1;
        }

#        $stdin->push_read($cb);
        return;
    };
    $stdin->push_read($cb);

#    printf "$Coro::current exiting _define_automation\n"; # DB 
    return $state;
};

# FIXME check code for possible self-ref closures which may cause mem leaks


sub login_async {
    my $self = shift;
    my ($passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' }, # fixme should be optional
    );
    my $done = AnyEvent->condvar;

    my $stdin = $self->delegate('pty')->handle;
    my $stderr = $self->delegate('stderr')->handle;

    $self->_error_event->cb(sub {
#        print "_error_event sent\n"; # DB
        $done->croak(shift->recv);
    });

    my $timeout;
    $timeout = AnyEvent->timer(
        after => $login_timeout_secs, 
        cb    => sub { 
            undef $timeout;
#            print "timing out login\n"; # DB
            $done->croak("Login timed out after $login_timeout_secs seconds");
        },
    );

    # capture stderr output, interpret as an error
    $stderr->on_read(sub {
        return unless my $text = shift->rbuf;
        $done->croak("error: $text");
    });

    $self->_define_automation(
        start => sub {
            if (_match($stdin => $passwd_prompt_re)) {
                _push_write($stdin => "$passwd\n");
                return 'sent_passwd';
            }
            
            if (_match($stdin => $initial_prompt_re)) {
                _push_write($stdin => qq(PS1="$prompt"; export PS1\n));
                return 'expect_prompt';
            }
            # FIXME limit buffer size and time
            return 'start';
        },
        
        sent_passwd => sub {
            if (_match($stdin => $passwd_prompt_re)) {
                my $msg = $stderr->{rbuf} || '';
                $done->croak("auth failure: $msg");
                return 'auth_failure';
            }
            
            if (_match($stdin => $initial_prompt_re)) {
                _push_write($stdin => qq(PS1="$prompt"; export PS1\n));
                return 'expect_prompt';
            }
            
            return 'sent_passwd';
        },
        
        expect_prompt => sub {
            if (_match($stdin => $prompt_re)) {
                # Cancel stderr monitor
                $stderr->on_read();

                $done->send($stdin, $self); # done
                return 'finished';
            }
            
            return 'expect_prompt';
        },
        
        auth_failure => 0,
        finished => 0,
    );

    return $done;
}

    

sub logout {
    my $self = shift;
    _push_write($self->delegate('pty')->handle => "exit\n");
    return $self;
}

sub capture_async {
    my $self = shift;
    my ($cmd) = pos_validated_list(
        \@_,
        { isa => 'Str' },
    );

    my $stdin = $self->delegate('pty')->handle;

    $cmd =~ s/\s*\z/\n/ms;

    # send command
    _push_write($stdin => $cmd);

    # read result
    my $cumdata = '';

    # we want the _error_event condvar to trigger a croak sent to $done.
    my $done = AnyEvent->condvar;
    # FIXME check _error_event for expiry?
    $self->_error_event->cb(sub {
#        print "xxxx _error_event\n"; # DB
        $done->croak(shift->recv);
    });

    my $read_output_cb = sub {
        my ($handle) = @_;
        return unless defined $handle->{rbuf};
        
#        print "got: $handle->{rbuf}\n"; # DB
        
        $cumdata .= $handle->{rbuf};
        $handle->{rbuf} = '';
        
        $cumdata =~ /(.*?)$prompt_re/ms
            or return;

        $done->send($handle, $1);
        return 1;
    };
    
    $stdin->push_read($read_output_cb);
    
    return $done;
}


sub capture {
    return (shift->capture_async(@_)->recv)[1];
}


sub sudo_capture_async {
    my $self = shift;
    my ($cmd, $passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' },
        { isa => 'Str' },
    );
    my $done = AnyEvent->condvar;
    $self->_error_event->cb(sub { 
#        print "_error_event sent\n"; DB
        $done->croak(shift->recv);
    });

    my $stdin = $self->delegate('pty')->handle;
    my $stderr = $self->delegate('stderr')->handle;

    my $timeout;
    $timeout = AnyEvent->timer(
        after => $login_timeout_secs, 
        cb    => sub { 
            undef $timeout;
#            print "timing out login\n"; # DB
            $done->croak("Login timed out after $login_timeout_secs seconds");
        },
    );

    # capture stderr output, interpret as an error
    $stderr->on_read(sub {
        return unless my $text = shift->rbuf;
        $done->croak("error: $text");
    });

    # ensure command has a trailing newline
    $cmd =~ s/\s*\z/\n/ms;

    # get captured result here
    my $cumdata = '';

# FIXME escape/untaint $passwd_prompt_re
# use full path names

    # Authenticate. Erase any cached sudo authentication first - we
    # want to guarantee that we will get a password prompt.  Then
    # start a new shell with sudo.
    _push_write($stdin => "sudo -K; sudo -p '$sudo_passwd_prompt' sh\n");

    $self->_define_automation(
        start => sub {
            if (_match($stdin => $sudo_passwd_prompt_re)) {
#                print "sending password\n"; # DB
                _push_write($stdin => "$passwd\n");
                return 'sent_passwd';
            }
            
            # FIXME limit buffer size and time
            return 'start';
        },
        
        sent_passwd => sub {
            if (_match($stdin => $sudo_passwd_prompt_re)) {
                my $msg = $stderr->{rbuf} || '';
                $done->croak("auth failure: $msg");
                return 'auth_failure';
            }
            
            if (_match($stdin => $prompt_re)) {
                _push_write($stdin => qq(PS1="$prompt"; export PS1\n));
                return 'expect_sudo_prompt';
            }
            
            return 'sent_passwd';
        },
        
        expect_sudo_prompt => sub {
            if (_match($stdin => $prompt_re)) {
                # Cancel stderr monitor
                $stderr->on_read();

                _push_write($stdin => $cmd);
                return 'expect_prompt';
            }
            
            return 'expect_sudo_prompt';
        },
        
        expect_prompt => sub {
            if (my ($data) = _match($stdin => qr/(.*?)$prompt_re/sm)) {
                $cumdata .= $data;
#                print "got data: $data\n<$stdin->{rbuf}>\n"; # DB

                $stdin->{rbuf} = '';

                # capture stderr output, interpret as a warning
                $stderr->on_read(sub {
                    return unless my $text = shift->rbuf;
                     warn "error on exiting: $text";
                });

                # exit sudo shell
                _push_write($stdin => "exit\n");
                
                return 'exited_shell';
            }
            
            $cumdata .= $stdin->{rbuf};
            $stdin->{rbuf} = '';
            return 'expect_prompt';
        },

        exited_shell => sub {
            if (_match($stdin => $prompt_re)) {
                # Cancel stderr monitor
                $stderr->on_read();

                # remove any output from the exit
                # FIXME should this check that everything has been consumed?
                $stdin->{rbuf} = ''; 

                $done->send($stdin, $cumdata); # done, send data collected
                return 'finished';
            }
            
            return 'exited_shell';
        },

        auth_failure => 0,
        finished => 0,
    );

    return $done;
}

sub sudo_capture {
    return (shift->sudo_capture_async(@_)->recv)[1];
}


__PACKAGE__->meta->make_immutable;
1;
