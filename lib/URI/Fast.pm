=head1 SYNOPSIS

  use URI::Fast qw(uri);

  my $uri = uri 'http://www.example.com/some/path?a=b&c=d';

  if ($uri->scheme =~ /http(s)?/) {
    my @path = $uri->split_path;
    my $a = $uri->param('a');
    my $b = $uri->param('b');
  }

  # Use faster URI constructor
  use URI::Fast qw(fast_URI);
  my $uri = fast_URI 'http://www.example.com/some/path?a=b&c=d';

=head1 DESCRIPTION

L<URI> is an excellent module. It is battle-tested, robust, and at this point
handles nearly every edge case imaginable. It is often the case, however, that
one just needs to grab the path string out of a URL. Or validate some query
parameters. Et cetera. In those cases, L<URI> may seem like overkill and may,
in fact, be much slower than a simpler solution, like L<URI::Split>.
Unfortunately, L<URI::Split> is so bare bones that it does not even parse the
authorization section or access query parameters.

C<URI::Fast> aims to bridge the gap between the two extremes. It provides fast
parsing without many of the frills of L<URI> while at the same time providing
I<slightly> more than L<URI::Split> by returning an object with methods to
access portions of the URI.

=head1 EXPORTED SUBROUTINES

=head2 uri

Accepts a string, minimally parses it (using L<URI::Split>), and returns a
L<URI::Fast> object.

When initially created, only the scheme, authorization section, path, query
string, and fragment are split out. Breaking these down further is done as
needed.

=head2 fast_URI

Returns an instance of L<URI> or the appropriate subclass, if available. It
does this faster than the URI constructor does by skipping some of the edge
cases it guards against, such as unwrapping, stringifying refs, and trimming
leading and trailing spaces.

=head1 ATTRIBUTES

=head2 scheme

Defaults to C<file> if not present in the uri string.

=head2 auth

The authorization section is composed of any the username, password, host name,
and port number.

  someone:secret@hostname.com:1234

Accessing the following attributes may incur a small amount of extra overhead
the first time they are called and the auth string is parsed.

=over

=item usr

=item pwd

=item host

=item port

=back

=head2 path

The entire path string. Trailing slashes are removed.

=over

=item split_path

Returns the path as an array ref of each segment, split by C</>. The separator
(forward slash) is excluded from the strings.

=back

=head2 query

The complete query string. Does not include the leading C<?>.

=over

=item param

Gets a parameter value. The first time this is called, it incurs the overhead
of parsing and decoding the query string.

If the key appears more than once in the query string, the value returned will
be an array ref of each of its values.

=back

=head2 frag

The fragment section of the URI, excluding the leading C<#>.

=cut

package URI::Fast;
# ABSTRACT: A fast URI parser

use common::sense;
use URI::Split qw(uri_split uri_join);
use URI::Encode::XS qw(uri_decode);

use parent 'Exporter';
our @EXPORT_OK = qw(uri fast_URI);

sub uri ($) {
  my $self = bless {}, __PACKAGE__;
  @{$self}{qw(scheme auth path query frag)} = uri_split $_[0];
  $self->{path} =~ s/\/$//;
  $self->{scheme} //= 'file';
  $self;
}

# Build a simple accessor for basic attributes
foreach my $attr (qw(scheme auth path query frag)) {
  *{__PACKAGE__ . "::$attr"} = sub {
    $_[0]->{$attr};
  };
}

# For bits of the auth string, build a lazy accessor that calls _auth, which
# parses the auth string.
foreach my $attr (qw(usr pwd host port)) {
  *{__PACKAGE__ . "::$attr"} = sub {
    $_[0]->{auth} && $_[0]->{_auth} || $_[0]->_auth;
    $_[0]->{$attr};
  };
}

# Parses auth strings
sub _auth {
  $_[0]->{_auth} = 1;                             # Set a flag to prevent reparsing

  if (local $_ = $_[0]->auth) {
    my ($cred, $loc) = split /@/;                 # usr:pwd@host:port

    if ($loc) {
      @{$_[0]}{qw(usr pwd)}   = split ':', $cred; # Both credentials and location are present
      @{$_[0]}{qw(host port)} = split ':', $loc;
    }
    else {
      @{$_[0]}{qw(host port)} = split ':', $cred; # Only location is present
    }
  }
}

# Returns a list of path segments, including the leading slash
sub split_path {
  local $_ = $_[0]->{path};
  s/^\///;
  split /\//;
}

sub param {
  $_[0]->{query} || return;

  if (!$_[0]->{param}) {
    my %param;                                         # Somewhere to set our things

    if (local $_ = $_[0]->{query}) {                   # Faster access via a dynamic variable
      tr/\+/ /;                                        # Seriously, dfarrell?
      local @_ = split /[&=]/;                         # Tokenize

      while (my $k = uri_decode(shift // '')) {        # Decode the next parameter
        if (exists $param{$k}) {                       # Multiple parameters exist with the same key
          $param{$k} = [$param{$k}]                    # Reinitialize as array ref to store multiple values
            unless ref $param{$k};

          push @{$param{$k}}, uri_decode(shift // ''); # Add to the array
        }
        else {                                         # First or only use of key
          $param{$k} = uri_decode(shift // '');
        }
      }
    }

    $_[0]->{param} = \%param;
  };

  $_[0]->{param}{$_[1]};
}

sub fast_URI ($) {
  require URI;

  local $_ = $_[0];
  m/^\s*([^:]+)(?=\/\/)/;

  my $ic;
  $ic = URI::implementor($1) // do {
    require URI::_foreign;
    $ic = 'URI::_foreign';
  };

  return $ic->_init($_, $1);
}

1;
