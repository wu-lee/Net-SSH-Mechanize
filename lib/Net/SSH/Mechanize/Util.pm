package Net::SSH::Mechanize::Util;
use strict;
use warnings;
use AnyEvent;

sub synchronize {
    shift;
    my $self = shift;
    my $method = shift;

    my $done = $self->$method(@_);
    my ($handle, $data) = $done->recv;
    return $data;
}

1;
