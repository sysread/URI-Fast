=head1 SYNOPSIS

  use URI::Fast qw(uri);

  my $uri = uri 'http://www.example.com/some/path?a=b&c=d';

  if ($uri->scheme =~ /http(s)?/) {
    my @path = $uri->path;
    my $a = $uri->param('a');
    my $b = $uri->param('b');
  }

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

In scalar context, returns the entire path string. In list context, returns a
list of path segments, split by C</>.

=over

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
use URI::Split qw(uri_split);
use URI::Encode::XS qw(uri_decode uri_encode);
use Carp;

use overload
  '""' => sub{
    my $s = "$_[0]->{scheme}://$_[0]->{auth}$_[0]->{path}";
    $s .= '?' . $_[0]->{query} if $_[0]->{query};
    $s .= '#' . $_[0]->{frag}  if $_[0]->{frag};
    $s;
  };

use parent 'Exporter';
our @EXPORT_OK = qw(uri);

our %LEGAL = (
  scheme => qr/^[a-zA-Z][-.+a-zA-Z0-9]*$/,
  port   => qr/^[0-9]+$/,
);

sub uri ($) {
  my $self = bless {}, __PACKAGE__;
  @{$self}{qw(scheme auth path query frag)} = uri_split $_[0];
  $self->{scheme} //= 'file';
  $self;
}

# Build a simple accessor for basic attributes
foreach my $attr (qw(scheme auth query frag)) {
  *{__PACKAGE__ . "::$attr"} = sub {
    if (@_ == 2) {
      !exists($LEGAL{$attr}) || $_[1] =~ $LEGAL{$attr} || croak "illegal chars in $attr";
      $_[0]->{$attr} = $_[1];
    }

    $_[0]->{$attr};
  };
}

# Path is slightly more complicated as it can parse the path
sub path {
  if (@_ == 2) {
    local $" = '/';           # Set list separator for string interpolation
    $_[0]->{path} = ref $_[1] # Check whether setting with list or string
      ? "/@{$_[1]}"           # List ref
      : $_[1];                # Scalar
  }

  if (wantarray) {
    local $_ = $_[0]->{path};
    s/^\///;
    split /\//;
  }
  else {
    $_[0]->{path};
  }
}

# For bits of the auth string, build a lazy accessor that calls _auth, which
# parses the auth string.
foreach my $attr (qw(usr pwd host port)) {
  *{__PACKAGE__ . "::$attr"} = sub {
    $_[0]->{auth} && $_[0]->{_auth} || $_[0]->_auth;

    # Set new value, then regenerate authorization section string
    if (@_ == 2) {
      !exists($LEGAL{$attr}) || $_[1] =~ $LEGAL{$attr} || croak "illegal chars in $attr";
      $_[0]->{$attr} = $_[1];
      $_[0]->_reauth;
    }

    $_[0]->{$attr};
  };
}

# Parses auth section
sub _auth {
  my ($self) = @_;
  $self->{_auth} = 1;                             # Set a flag to prevent reparsing

  if (local $_ = $self->auth) {
    my ($cred, $loc) = split /@/;                 # usr:pwd@host:port

    if ($loc) {
      @{$self}{qw(usr pwd)}   = split ':', $cred; # Both credentials and location are present
      @{$self}{qw(host port)} = split ':', $loc;
    }
    else {
      @{$self}{qw(host port)} = split ':', $cred; # Only location is present
    }
  }
}

# Regenerates auth section
sub _reauth {
  my $self = shift;
  $self->{auth} = '';

  if ($self->{usr}) {
    $self->{auth} = $self->{usr};
    $self->{auth} .= ':' . $self->{pwd} if $self->{pwd};
    $self->{auth} .= '@';
  }

  $self->{auth} .= $self->{host};

  if ($self->{port}) {
    $self->{auth} .= ':' . $self->{port};
  }
}

sub param {
  my ($self, $key, $val) = @_;
  $self->{query} || $val || return;

  if (!$self->{param}) {
    $self->{param} = {};                                       # Somewhere to set our things

    if (local $_ = $self->{query}) {                           # Faster access via a dynamic variable
      tr/\+/ /;                                                # Seriously, dfarrell?
      local @_ = split /[&=]/;                                 # Tokenize

      while (my $k = uri_decode(shift // '')) {                # Decode the next self->{param}eter
        if ($val && $k eq $key) {                              # We'll be setting this shortly, so ignore
          shift;
          next;
        }

        if (exists $self->{param}{$k}) {                       # Multiple self->{param}eters exist with the same key
          $self->{param}{$k} = [$self->{param}{$k}]            # Reinitialize as array ref to store multiple values
            unless ref $self->{param}{$k};

          push @{$self->{param}{$k}}, uri_decode(shift // ''); # Add to the array
        }
        else {                                                 # First or only use of key
          $self->{param}{$k} = uri_decode(shift // '');
        }
      }
    }
  };

  if ($val) {                                                  # Modifying this value
    $self->{param}{$key} = $val;                               # Update the pre-parsed hash ref

    $key = uri_encode($key);                                   # Encode the key
    $self->{query} =~ s/\b$key=[^&]+&?//;                      # Remove from the query string

    if (ref $val) {                                            # If $val is an array, each element gets its own place in the query
      foreach (@$val) {
        $self->{query} .= '&' if $self->{query};
        $self->{query} .= $key . '=' . uri_encode($_);
      }
    }
    else {                                                     # Otherwise, just add the encoded pair
      $self->{query} .= '&' if $self->{query};
      $self->{query} .= $key . '=' . uri_encode($val);
    }
  }

  $self->{param}{$key} if defined $key
}

1;
