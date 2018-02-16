=head1 SYNOPSIS

  use URI::Fast qw(uri_of_str str_of_uri);

  my $uri = uri_of_str 'http://www.example.com/some/path?a=b&c=d';
  $uri->param(a => 'not b anymore');  # update a query parameter
  $uri->param(b => undef);            # delete a query parameter
  $uri->user('somebody');             # modify the auth section

  my $str = str_of_uri $uri;          # http://somebody@www.example.com/some/path?a=not%20b%20anymore

=head1 DESCRIPTION

L<URI> is an excellent module. It is battle-tested, robust, and at this point
handles nearly every edge case imaginable. It is often the case, however, that
one just needs to grab the path string out of a URL. Or validate some query
parameters. Or switch the scheme from http to https.  Et cetera. In those
cases, L<URI> may seem like overkill and may, in fact, be much slower than a
simpler solution, like L<URI::Split>. Unfortunately, L<URI::Split> is so bare
bones that it does not even parse the authorization section or provide an
object that can be easily modified.

C<URI::Fast> aims to bridge the gap between the two extremes. It provides fast
parsing and string building without many of the frills of L<URI> while at the
same time providing I<slightly> more than L<URI::Split> by returning an object
with accessor methods to update the URI without resorting to string
replacement.

=head1 EXPORTED SUBROUTINES

=head2 str_of_uri

Accepts a L<URI::Fast> object and generates the URI string from it.

=head2 uri_of_str

Accepts a string, minimally parses it (using L<URI::Split>), and returns a
L<URI::Fast> object.

When initially created, only the scheme, authorization section, path, query
string, and fragment are split out. Breaking these down further is done as
needed.

=head1 ATTRIBUTES

=head2 uri

The URI string used to create the object.

=head2 scheme

Defaults to C<file> if not present in the uri string.

=head2 auth

The authorization section is composed of any the username, password, host name,
and port number.

  someone:secret@hostname.com:1234

Accessing the following attributes may incur a small amount of extra overhead
the first time they are called and the auth string is parsed. Using them to
update the values will cause the auth string to be regenerated.

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

Returns the path as an array ref of each segment, split by C</>.

=back

=head2 query

The complete query string. Does not include the leading C<?>.

=over

=item param

Gets or sets a parameter value. The first time this is called, it incurs the
overhead of parsing and decoding the query string. When used to modify the
query, the query string is updated with the encoded values.

=back

=head2 frag

The fragment section of the URI, excluding the leading C<#>.

=cut

package URI::Fast;
# ABSTRACT: A fast URI parser and builder

use common::sense;
use URI::Split qw(uri_split uri_join);
use URI::Encode::XS qw(uri_decode uri_encode);

use parent 'Exporter';
our @EXPORT_OK = qw(uri_of_str str_of_uri);

sub uri_of_str {
  my ($scheme, $auth, $path, $query, $frag) = uri_split $_[0];
  $path =~ s/\/$//; # trim trailing slashes from path

  bless {
    uri    => $_[0],
    scheme => $scheme || 'file',
    auth   => $auth,
    path   => $path,
    query  => $query,
    frag   => $frag,
  }, 'URI::Fast';
}

sub str_of_uri {
  uri_join @{$_[0]}{qw(scheme auth path query frag)};
}

# Build a simple accessor for basic attributes
do {
  foreach my $attr (qw(scheme auth path query frag)) {
    *{__PACKAGE__ . "::$attr"} = sub {
      if (@_ == 2) {
        $_[0]->{$attr} = $_[1];   # Is there a new value to be set?
        delete $_[0]->{"_$attr"}; # Delete the "parsed" flag
      }
      $_[0]->{$attr};             # Return the attribute value
    };
  }
};

# For bits of the auth string, build a lazy accessor that calls _auth, which
# parses the auth string.
do {
  foreach my $attr (qw(usr pwd host port)) {
    *{__PACKAGE__ . "::$attr"} = sub {
      $_[0]->_auth;
      return $_[0]->{$attr} if @_ == 1;

      if (@_ == 2) {
        $_[0]->{$attr} = $_[1];
        $_[0]->_rebuild_auth;
      }

      $_[0]->{$attr};
    };
  }
};

# Rebuilds auth string
sub _rebuild_auth {
  $_[0]->{auth} = '';

  if ($_[0]->{usr}) {
    $_[0]->{auth} .= $_[0]->{usr};
    $_[0]->{auth} .= ':' . $_[0]->{pwd} if $_[0]->{pwd};
  }

  if ($_[0]->{host}) {
    $_[0]->{auth} .= '@' if $_[0]->{auth};
    $_[0]->{auth} .= $_[0]->{host};
    $_[0]->{auth} .= ':' . $_[0]->{port} if $_[0]->{port};
  }

  undef $_[0]->{auth} unless $_[0]->{auth};
}

# Parses auth strings
sub _auth {
  do{
    $_[0]->{_auth} = 1;                             # Set a flag to prevent reparsing

    if ($_[0]->{auth}) {
      my ($cred, $loc) = split '@', $_[0]->{auth};  # usr:pwd@host:port

      if ($loc) {
        @{$_[0]}{qw(usr pwd)}   = split ':', $cred; # Both credentials and location are present
        @{$_[0]}{qw(host port)} = split ':', $loc;
      }
      else {
        @{$_[0]}{qw(host port)} = split ':', $cred; # Only location is present
      }
    }
  } if $_[0]->{auth} && !$_[0]->{_auth};
}

# Returns a list of path segments, including the leading slash
sub split_path {
  split /(?=\/)/, $_[0]->path;
}

sub param {
  do{
    $_[0]->{param} = {};                            # Somewhere to set our things

    if ($_ = $_[0]->{query}) {                      # Faster access via a dynamic variable
      tr/\+/ /;                                     # Really, dfarrell?
      my @fields = split /[&=]/;                    # Tokenize
      my $i = 0;

      while ($i < @fields) {
        my $k = uri_decode $fields[$i++];           # Decode the next parameter
        my $v = uri_decode $fields[$i++];           # ...and it's value

        if (exists $_[0]->{param}{$k}) {            # Multiple parameters exist with the same key
          $_[0]->{param}{$k} = [$_[0]->{param}{$k}] # Reinitialize as array ref to store multiple values
            unless ref $_[0]->{param}{$k};

          push @{$_[0]->{param}{$k}}, $v;           # Add to the array
        }
        else {                                      # First or only use of key
          $_[0]->{param}{$k} = $v;
        }
      }
    }
  } if $_[0]->{query} && !$_[0]->{param};

  $_[0]->set_param($_[1], $_[2]) if @_ == 3;
  $_[0]->{param}{$_[1]};
}

sub _encode_param {
  my ($k, $v) = @_;
  $k = uri_encode $k;
  return ref $v
    ? join('&', map{"$k=$_"} map{$_ ? uri_encode($_) : ''} @$v)
    : join('=', $k, $v ? uri_encode($v) : '');
}

sub set_param {
  my ($self, $k, $v) = @_;

  if (defined $v) {
    $self->{param}{$k} = $v;
  } else {
    delete $self->{param}{$k};
  }

  $self->{query} = join '&',
    map{ _encode_param($_, $self->{param}{$_}) }
    keys %{$self->{param}};
}

1;
