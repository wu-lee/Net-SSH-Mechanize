package Net::SSH::Mechanize::Util;
use strict;
use warnings;
use Coro;

sub synchronize {
    shift;
    my $self = shift;
    my $method = shift;
    $self->$method(@_, Coro::rouse_cb);
    my ($handle, $data) = Coro::rouse_wait;
    return $data;
}

1;
