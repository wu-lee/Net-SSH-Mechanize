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
# create a random text delimiter
my $delim = MIME::Base64::encode_base64 rand;
chomp $delim;

my $prompt_re = qr/$delim\Q$ \E$/m;

my $login_timeout_secs = 10;

has '_error_event' => (
    is => 'rw',
    isa => 'AnyEvent::CondVar',
    default => sub { return AnyEvent->condvar },
);

sub expect_async {
    my $self = shift;

    my $done = AnyEvent->condvar;

    # we want the _error_event condvar to trigger a croak sent to $done.
    # FIXME check _error_event for expiry?
    $self->_error_event->cb(sub { $done->croak(@_) });
    $self->delegate('completion_condvar')->condvar->cb(sub { $done->croak(@_) });

    $self->delegate('pty')->handle->push_read(@_, sub { 
                                                  my ($h, $d) = @_; # DB
                                                  print "got >$d< buf >", $h->rbuf, "<\n";
                                                  $done->send(@_) });

#    print "expecting @_\n"; # DB

    return $done;
}


sub expect {
    return (shift->expect_async->recv)[1];
}

sub push_write {
    my $self = shift;

#    print "writing @_\n"; # DB
    $self->delegate('pty')->handle->push_write(@_);
}


=for shelved



my $login = sub {
    _given $passwd_prompt_re => sub {
        $handle->push_write("$passwd\n");

        _given 
                $initial_prompt_re => sub {
                    $handle->push_write(qq(PS1="$delim\$ "; export PS1\n));

                    _expect(
                        $prompt_re => sub {
                            _done;
                        },
                    );
                },
            );
        },
        $resolution_error_re => sub {
            _error; # with appropriate message
        },
    );
}; 

start
 ? password prompt
   < passwd
   ? initial prompt
     < PS1=$prompt
     ? prompt
       done  
     : error
   : permission denied error
   : other error
 : resolution error 
 : other errors



=cut        


# helper function
sub _match {
    my $handle = shift;
    my $re = shift;
    return unless $handle->{rbuf};
    print "$Coro::current $handle got <$handle->{rbuf}>\n"; # DB    
    my @captures = $handle->{rbuf} =~ /$re/
        or return;
    print "$Coro::current matched $re with: <$handle->{rbuf}>\n"; # DB

    substr $handle->{rbuf}, 0, $+[0], "";
    return @captures;
}

sub _define_automation {
    my $self = shift;
    my %states = @_;

    my ($stdin, $stderr) = map { $self->delegate($_)->handle } qw(pty stderr);

    my $state = 'start';
    my $cb;
    $cb = sub {
        printf "$Coro::current $stdin before: state is %s\n", $state;
        $state = $states{$state}->(@_);
        exists $states{$state}
            or die "something is wrong, next state returned is undefined ($state)";

        printf "$Coro::current after: state is %s\n", $state;
        if (!$states{$state}) { # terminal state, stop reading
 #           $stderr->on_read(); # cancel errors on stderr
            $stdin->{rbuf} = '';
            return 1;
        }

#        $stdin->push_read($cb);
        return;
    };
    $stdin->push_read($cb);

    printf "$Coro::current exiting _define_automation\n";
    return $state;
};




sub login_async {
    my $self = shift;
    my ($passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' }, # fixme should be optional
    );
    my $done = AnyEvent->condvar;

    my $stdin = $self->delegate('pty')->handle;
    my $stderr = $self->delegate('stderr')->handle;

    my $timeout;
    $timeout = AnyEvent->timer(
        after => $login_timeout_secs, 
        cb    => sub { 
            undef $timeout;
            print "timing out login\n"; # DB
            $done->croak("Login timed out after $login_timeout_secs seconds");
        },
    );


    $self->_define_automation(
        start => sub {
            if (_match($stdin => $passwd_prompt_re)) {
                $stdin->push_write("$passwd\n");
                return 'sent_passwd';
            }
            
            if (_match($stdin => $initial_prompt_re)) {
                $stdin->push_write(qq(PS1="$delim\$ "; export PS1\n));
                return 'expect_prompt';
            }
            # limit buffer size and time
            return 'start';
        },
        
        sent_passwd => sub {
            if (_match($stdin => $passwd_prompt_re)) {
                my $msg = $stderr->{rbuf} || '';
                $stderr->{rbuf} = '';
                $done->croak("auth failure: $msg");
                return 'auth_failure';
            }
            
            if (_match($stdin => $initial_prompt_re)) {
                $stdin->push_write(qq(PS1="$delim\$ "; export PS1\n));
                return 'expect_prompt';
            }
            
            return 'sent_passwd';
        },
        
        expect_prompt => sub {
            if (_match($stdin => $prompt_re)) {
                # success - but check for any stderr output and warn if there is any
                #$stderr->on_read(); # cancel errors on stderr
                warn "unexpected output on stderr whilst logging in:\n", $stderr->{rbuf}
                    if $stderr->{rbuf};
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

sub login_async_deleteme {
    my $self = shift;
    my ($passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' }, # fixme should be optional
    );
    my $done = AnyEvent->condvar;

    my $stdin = $self->delegate('pty')->handle;
    my $stderr = $self->delegate('stderr')->handle;

    my $match = sub { 
        my $re = shift;
        return unless $stdin->{rbuf};
        my @captures = $stdin->{rbuf} =~ /$re/
            or return;
#        print "$self matched $re with: <$stdin->{rbuf}>\n"; # DB

        substr $stdin->{rbuf}, 0, $+[0], "";
        return @captures;
    };

    my $states = {
        start => sub {
            if ($match->($passwd_prompt_re)) {
                $stdin->push_write("$passwd\n");
                return 'sent_passwd';
            }
            
            if ($match->($initial_prompt_re)) {
                $stdin->push_write(qq(PS1="$delim\$ "; export PS1\n));
                return 'expect_prompt';
            }
            # limit buffer size and time
            return 'start';
        },
        
        sent_passwd => sub {
            if ($match->($passwd_prompt_re)) {
                my $msg = $stderr->{rbuf} || '';
                $stderr->{rbuf} = '';
                $done->croak("auth failure: $msg");
                return 'auth_failure';
            }
            
            if ($match->($initial_prompt_re)) {
                $stdin->push_write(qq(PS1="$delim\$ "; export PS1\n));
                return 'expect_prompt';
            }
            
            return 'sent_passwd';
        },
        
        expect_prompt => sub {
            if ($match->($prompt_re)) {
                # success - but check for any stderr output and warn if there is any
                #$stderr->on_read(); # cancel errors on stderr
                warn "unexpected output on stderr whilst logging in:\n", $stderr->{rbuf}
                    if $stderr->{rbuf};
                $done->send($stdin, $self); # done
                return 'finished';
            }
            
            return 'expect_prompt';
        }
    };

    # error: 
    # anything on stderr
    # any failures signalled

#    $stderr->on_read(sub { $done->croak("stderr output: ". $stderr->{rbuf} || '') });

    my $state = 'start';
    my $cb;
    $cb = sub {
#        printf "before: state is %s, done is %s\n", $state, !!$done->ready;
        $state = $states->{$state}->(@_);
#        printf "after: state is %s, done is %s\n", $state, !!$done->ready;
        if ($done->ready) { # stop reading
 #           $stderr->on_read(); # cancel errors on stderr
            $stdin->{rbuf} = '';
            return 1;
        }

        $state
            or die "something is wrong, state didn't return a next state";
#        $stdin->push_read($cb);
        return;
    };
    $stdin->push_read($cb);

    return $done;
};

    


=for shelved

sub login_async {
    my $self = shift;
    my ($passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' },
    );
    my $done = AnyEvent->condvar;

    my $handle = $self->delegate('pty')->handle;
    my $stderr = $self->delegate('stderr')->handle;
    my $data = '';

    $handle->push_read(sub {
	return unless $handle->{rbuf};
	my $rbuf = \$handle->{rbuf};
	if ($$rbuf =~ $passwd_prompt_re) {
	    printf "got passwd prompt:> %s<\n", # DB
	    substr $$rbuf, 0, $+[0], "";

	    $handle->push_write("$passwd\n");
            
	    my $cb; $cb = sub {
		$rbuf = \$handle->{rbuf};
		print "looking for initial prompt\n"; # DB
		if ($$rbuf =~ $initial_prompt_re) {
		    printf "got initial prompt:> %s<\n", # DB
		    substr $$rbuf, 0, $+[0], "";
		    $handle->push_write(qq(PS1="$delim\$ "; export PS1\n));
		    
		    $handle->push_read(sub {
			$rbuf = \$handle->{rbuf};
			if ($$rbuf =~ $prompt_re) {
			    substr $$rbuf, 0, $+[0], "";
                            $done->send($handle, $self);
			    return 1;
			}
			else {
			    $done->croak("no prompt found");
                            return 1; 
			}
		    });
		}
		elsif ($$rbuf =~ /permission denied.*$/mi) {
		    my $error = substr $$rbuf, 0, $+[0], "";
		    $done->croak("permission denied: $error"); # FIXME formatting
		    return 1;
		}
		else {
		    printf "looking: >%s<\n", $$rbuf;
		    printf "stderr: >%s<\n", $stderr->rbuf;
		    $handle->push_read($cb);
		    return; # keep looking
		}
	    };
	    $handle->push_read($cb);
	    return 1;
	}
        elsif ($$rbuf =~ /could not resolve.*$/mi) {
	    $done->croak("unknown host");
	    return 1;     # with appropriate message
        }
        else {
	    $done->croak("connection error");
	    return 1;
	}
    }); 

    return $done;
}

=cut

=for shelved

sub login_async {
    my $self = shift;
    my ($passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' },
    );
    my $done = AnyEvent->condvar;

    my $handle = $self->delegate('pty')->handle;

    $handle->push_read(sub {
        my $rbuf = \$handle->{rbuf};
        if ($$rbuf =~ /$passwd_prompt_re/) {
            $handle->push_write("$passwd\n");

            $handle->push_read(sub {
                my $rbuf = \$handle->{rbuf};
                if ($$rbuf =~ /$initial_prompt_re/) {

                    $done->send();
                    return 1;
                }
                else {

                }
            });
        }
        elsif ($$rbuf =~ /could not resolve.*$/m) {

        }
        else {

        }
    });               

regex => qr/$passwd_prompt_re|$initial_prompt_re|could not resolve.*$/m)->cb(sub {
        my ($h, $d) = shift->recv;
        if ($d =~ /$passwd_prompt_re/) { # we need to give the password
            $self->push_write("$passwd\n");

            # expect initial prompt; bad passwd; anything else
            $self->expect_async(regex => $initial_prompt_re, qr/permission denied.*$/ism)->cb(sub {
                my ($h, $d) = shift->recv;
                $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

                $self->expect_async(regex => $prompt_re)->cb(sub {
                    my ($h, $d) = shift->recv;
                    $done->send($h, $self);
                });
            });
        }
        else { # no password prompt
            $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

            $self->expect_async(regex => $prompt_re)->cb(sub {
                my ($h, $d) = shift->recv;
                $done->send($h, $self);
            });
        }
    });

    return $done;
}

sub login_async {
    my $self = shift;
    my ($passwd) = pos_validated_list(
        \@_,
        { isa => 'Str' },
    );
    my $done = AnyEvent->condvar;

    $self->expect_async(regex => qr/$passwd_prompt_re|$initial_prompt_re|could not resolve.*$/m)->cb(sub {
        my ($h, $d) = shift->recv;
        if ($d =~ /$passwd_prompt_re/) { # we need to give the password
            $self->push_write("$passwd\n");

            # expect initial prompt; bad passwd; anything else
            $self->expect_async(regex => $initial_prompt_re, qr/permission denied.*$/ism)->cb(sub {
                my ($h, $d) = shift->recv;
                $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

                $self->expect_async(regex => $prompt_re)->cb(sub {
                    my ($h, $d) = shift->recv;
                    $done->send($h, $self);
                });
            });
        }
        else { # no password prompt
            $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

            $self->expect_async(regex => $prompt_re)->cb(sub {
                my ($h, $d) = shift->recv;
                $done->send($h, $self);
            });
        }
    });

    return $done;
}

=cut

# FIXME this not get called ever?
sub login {
    return (shift->login_async(@_)->recv)[1];
}


sub logout {
    my $self = shift;
    $self->push_write("exit\n");
    return $self;
}

sub capture_async {
    my $self = shift;
    my ($cmd) = pos_validated_list(
        \@_,
        { isa => 'Str' },
    );

    $cmd =~ s/\s*\Z/\n/ms;

    # send command
    $self->push_write($cmd);

    # read result
    my $cumdata = '';

    # we want the _error_event condvar to trigger a croak sent to $done.
    my $done = AnyEvent->condvar;
    # FIXME check _error_event for expiry?
    $self->_error_event->cb(sub { $done->croak(@_) });

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
    
    $self->delegate('pty')->handle->push_read($read_output_cb);
    
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

    # Erase any cached sudo authentication - we want to guarantee that
    # expect will negotiate a password prompt.
    $self->push_write("sudo -K\n");

    # Now authenticate using sudo
    my $passwd_prompt = "$delim-passwd:";
    $self->push_write("sudo -p $passwd_prompt sh\n");
    $self->expect_async(regex => qr/$passwd_prompt$/sm)->cb(sub {
        $self->push_write("$passwd\n");
        $self->push_write(qq(PS1="$delim\$ "; export PS1\n));

        $self->expect_async(regex => $prompt_re)->cb(sub {
            $self->capture_async($cmd)->cb(sub {
                 my ($handle, $data) = shift->recv;

                 $self->logout;
                 $self->expect_async(regex => $prompt_re)->cb(sub {
                     my ($handle) = shift->recv;
                     $done->send($handle, $data);
                 });
            });
        });
    });

    return $done;
}

sub sudo_capture {
    return (shift->sudo_capture_async(@_)->recv)[1];
}


__PACKAGE__->meta->make_immutable;
1;
