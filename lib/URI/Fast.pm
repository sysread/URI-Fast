package URI::Fast;

# ABSTRACT: A fast(er) URI parser

use common::sense;
use utf8;
use Carp;
use Inline C => 'lib/uri_fast.c';
use Encode qw();

require Exporter;
use parent 'Exporter';
our @EXPORT_OK = qw(uri uri_split);

use overload '""' => sub{ $_[0]->to_string };

sub uri ($) {
  my $self = URI::Fast->new($_[0] // '');
  $self->set_scheme('file', 0) unless $self->get_scheme;
  $self;
}

# Build a simple accessor for basic attributes
foreach my $attr (qw(scheme usr pwd host port frag)) {
  my $s = "set_$attr";
  my $g = "get_$attr";

  *{__PACKAGE__ . "::$attr"} = sub {
    if (@_ == 2) {
      $_[0]->$s($_[1], 0);
    }

    if (defined wantarray) {
      # It turns out that it is faster to call decode here than directly in
      # url_fast.c due to the overhead of decoding utf8 and flipping the
      # internal utf8 switch.
      return decode( $_[0]->$g() );
    }
  };
}

sub auth {
  my ($self, $val) = @_;

  if (@_ == 2) {
    if (ref $val) {
      $self->set_auth('', 1);
      $self->set_usr($val->{usr}   // '', 1);
      $self->set_pwd($val->{pwd}   // '', 1);
      $self->set_host($val->{host} // '', 1);
      $self->set_port($val->{port} // '', 0);
    }
    else {
      $self->set_auth($val, 0);
    }
  }

  return $self->get_auth
    if defined wantarray;
}

# Path is slightly more complicated as it can parse the path
sub path {
  my ($self, $val) = @_;

  if (@_ == 2) {
    $val = '/' . join '/', @$val if ref $val;
    $self->set_path($val, 0);
  }

  if (wantarray) {
    return $self->split_path;
  }
  elsif (defined wantarray) {
    return decode($self->get_path);
  }
}

# Queries may be set with either a string or a hash ref
sub query {
  my ($self, $val) = @_;

  if (@_ == 2) {
    if (ref $val) {
      $self->set_query('', 1);

      foreach (keys %$val) {
        $self->param($_, $val->{$_});
      }
    }
    else {
      $self->set_query($val, 0);
    }
  }

  return $self->get_query
    if defined wantarray;
}

sub query_keys {
  my @keys = $_[0]->get_query_keys;
  my %uniq;
  @uniq{@keys} = (1) x @keys;
  keys %uniq;
}

sub param {
  my ($self, $key, $val) = @_;

  if (@_ == 3) {
    $key = encode_reserved($key, '');
    my $query = $self->get_query;

    if ($query =~ /$key/) {
      # Wipe out current values for $key
      $query =~ s/\b$key=[^&#]+&?//g;
      $query =~ s/^&//;
      $query =~ s/&$//;
    }

    # If $val is undefined, the parameter is deleted
    if (defined $val) {
      # Encode and attach values for param to query string
      foreach (ref $val ? @$val : ($val)) {
        $query .= '&' if $query;
        $query .= $key . '=' . encode_reserved($_, '');
      }
    }

    $self->set_query(encode_utf8($query), 0);
  }

  # No return value in void context
  return unless defined(wantarray) && $key;

  my @params = $self->get_param(encode($key, ''))
    or return;

  return @params == 1
    ? $params[0]
    : \@params;
}

=head1 SYNOPSIS

  use URI::Fast qw(uri);

  my $uri = uri 'http://www.example.com/some/path?a=b&c=d';

  if ($uri->scheme =~ /http(s)?/) {
    my @path = $uri->path;
    my $a = $uri->param('a');
    my $b = $uri->param('b');
  }

  if ($uri->path =~ /\/login/ && $uri->scheme ne 'https') {
    $uri->scheme('https');
    $uri->param('upgraded', 1);
  }

=head1 DESCRIPTION

<URI::Fast> is a faster alternative to L<URI>. It is written in C and provides
basic parsing and modification of a URI.

L<URI> is an excellent module; it is battle-tested, robust, and handles many
edge cases. As a result, it is rather slower than it would otherwise be for
more trivial cases, such as inspecting the path or updating a single query
parameter.

=head1 EXPORTED SUBROUTINES

=head2 uri

Accepts a URI string, minimally parses it, and returns a L<URI::Fast> object.

=head1 ATTRIBUTES

Unless otherwise specified, all attributes serve as full accessors, allowing
the URI segment to be both retrieved and modified.

=head2 scheme

Defaults to C<file> if not present in the URI string.

=head2 auth

The authorization section is composed of the username, password, host name, and
port number:

  hostname.com
  someone@hostname.com
  someone:secret@hostname.com:1234

Setting this field may be done with a string (see the note below about
L</ENCODING>) or a hash reference of individual field names (C<usr>, C<pwd>,
C<host>, and C<sport>). In both cases, the existing values are completely
replaced by the new values and any values not present are deleted.

=head3 usr

The username segment of the authorization string. Updating this value alters
L</auth>.

=head3 pwd

The password segment of the authorization string. Updating this value alters
L</auth>.

=head3 host

The host name segment of the authorization string. May be a domain string or an
IP address. Updating this value alters L</auth>.

=head3 port

The port number segment of the authorization string. Updating this value alters
L</auth>.

=head2 path

In scalar context, returns the entire path string. In list context, returns a
list of path segments, split by C</>.

The path may also be updated using either a string or an array ref of segments:

  $uri->path('/foo/bar');
  $uri->path(['foo', 'bar']);

=head2 query

The complete query string. Does not include the leading C<?>.

=head2 query_keys

Does a fast scan of the query string and returns a list of unique parameter
names that appear in the query string.

=head3 param

Gets or sets a parameter value. If the key appears more than once in the query
string, returns an array ref of all values.

Setting a parameter value will update the L</query> string. Setting a parameter
to C<undef> deletes the parameter from the URI.

=head2 frag

The fragment section of the URI, excluding the leading C<#>.

=head1 ENCODING

C<URI::Fast> tries to do the right thing in most cases with regard to reserved
and non-ASCII characters. C<URI::Fast> will fully encode reserved and non-ASCII
characters when setting C<individual> values. However, the "right thing" is a
bit ambiguous when it comes to setting compound fields like L</auth>, L</path>,
and L</query>.

When setting these fields with a string value, reserved characters are expected
to be present, and are therefore accepted as-is. However, any non-ASCII
characters will be percent-encoded (since they are unambiguous and there is no
risk of double-encoding them).

  $uri->auth('someone:secret@Ῥόδος.com:1234');
  print $uri->auth; # "someone:secret@%E1%BF%AC%CF%8C%CE%B4%CE%BF%CF%82.com:1234"

On the other hand, when setting these fields with a I<reference> value, each
field is fully percent-encoded:

  $uri->auth({usr => 'some one', host => 'somewhere.com'});
  print $uri->auth; # "some%20one@somewhere.com"

The same goes for return values. For compound fields returning a string,
non-ASCII characters are decoded but reserved characters are not. When
returning a list or reference of the deconstructed field, individual values are
decoded of both reserved and non-ASCII characters.

=head1 SPEED

See L<URI::Fast::Benchmarks>.

=head1 SEE ALSO

=over

=item L<URI>

The de facto standard.

=item L<Panda::URI>

Written in C++ and purportedly very fast, but appears to only support Linux.

=back

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com> for encouraging their
employees to contribute back to the open source ecosystem. Without their
dedication to quality software development this distribution would not exist.

=cut

1;
