package URI::Fast::Test;

use strict;
use warnings;
use Test2::V0;

use parent 'Exporter';

our @EXPORT = qw(is_same_uri isnt_same_uri);

sub _data {
  return {
    scheme => $_[0]->scheme,
    usr    => $_[0]->usr,
    pwd    => $_[0]->pwd,
    host   => $_[0]->host,
    port   => $_[0]->port,
    path   => [$_[0]->path],
    query  => $_[0]->query_hash,
    frag   => $_[0]->frag,
  },
}

sub is_same_uri {
  my ($got, $expected, $msg) = @_;
  is _data($got), _data($expected), $msg;
}

sub isnt_same_uri {
  my ($got, $expected, $msg) = @_;
  isnt _data($got), _data($expected), $msg;
}

1;

=head1 NAME

URI::Fast::Test

=head1 SYNOPSIS

  use URI::Fast qw(uri);
  use URI::Fast::Test;

  is_same_uri uri($got), uri($expected), 'got expected uri';

  isnt_same_uri uri($got), uri($unwanted), 'did not get unwanted uri';

=head1 EXPORTS

=head2 is_same_uri

Builds a nested structure of uri components for comparison with Test2's deep
comparison using C<is>.

=head2 isnt_same_uri

Builds a nested structure of uri components for comparison with Test2's deep
comparison using C<isnt>.

=cut
