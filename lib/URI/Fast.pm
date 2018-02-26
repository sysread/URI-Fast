package URI::Fast;
# ABSTRACT: A fast(er) URI parser

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

L<URI> is an excellent module. It is battle-tested, robust, and at this point
handles nearly every edge case imaginable. It is often the case, however, that
one just needs to grab the path string out of a URL. Or validate some query
parameters. Et cetera. In those cases, L<URI> may seem like overkill and may,
in fact, be much slower than a simpler solution, like L<URI::Split>.
Unfortunately, L<URI::Split> is so bare bones that it does not even parse the
authorization section or access or update query parameters.

C<URI::Fast> aims to bridge the gap between the two extremes. It provides fast
parsing without many of the frills of L<URI> while at the same time providing
I<slightly> more than L<URI::Split> by returning an object with methods to
access and update portions of the URI.

=head1 EXPORTED SUBROUTINES

=head2 uri

Accepts a string, minimally parses it, and returns a L<URI::Fast> object.

When initially created, only the scheme, authorization section, path, query
string, and fragment are split out. Thesea are broken down in a lazy fashion
as needed when a related attribute accessor is called.

=head1 ATTRIBUTES

Unless otherwise specified, all attributes serve as full accessors, allowing
the URI segment to be both retrieved and modified.

=head2 scheme

Defaults to C<file> if not present in the uri string.

=head2 auth

The authorization section is composed of the username, password, host name, and
port number:

  hostname.com
  someone@hostname.com
  someone:secret@hostname.com:1234

Accessing the following attributes may incur a small amount of extra overhead
the first time they are called and the auth string is parsed.

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

=head3 param

Gets or sets a parameter value. The first time this is called, it incurs the
overhead of parsing and decoding the query string.

If the key appears more than once in the query string, the value returned will
be an array ref of each of its values.

Setting the parameter will update the L</query> string.

=head2 frag

The fragment section of the URI, excluding the leading C<#>.

=head1 SPEED

See L<URI::Fast::Benchmarks>.

=head1 SEE ALSO

=over

=item L<URI>

The de facto standard.

=item L<Panda::URI>

Written in C++ and purportedly very fast, but appears to only support Linux.

=back

=cut

use common::sense;
use Carp;
use Inline 'C';
use URI::Encode::XS qw(uri_encode uri_decode);
require Exporter;

use parent 'Exporter';
our @EXPORT_OK = qw(uri uri_split auth_split query_split);

use overload
  '""' => sub{
    "$_[0]->{scheme}://$_[0]->{auth}$_[0]->{path}"
      . ($_[0]->{query} ? ('?' . $_[0]->{query}) : '')
      . ($_[0]->{frag}  ? ('#' . $_[0]->{frag})  : '');
  };


# Regexes used to validate characters present in string when attributes are
# updated.
our %LEGAL = (
  scheme => qr/^[a-zA-Z][-.+a-zA-Z0-9]*$/,
  port   => qr/^[0-9]+$/,
);

sub uri ($) {
  my $self = bless {}, __PACKAGE__;
  @{$self}{qw(scheme auth path query frag)} = uri_split($_[0]);
  $self->{scheme} //= 'file';
  $self;
}

# Build a simple accessor for basic attributes
foreach my $attr (qw(scheme auth query frag)) {
  *{__PACKAGE__ . "::$attr"} = sub {
    if (@_ == 2) {
      !exists($LEGAL{$attr}) || $_[1] =~ $LEGAL{$attr} || croak "illegal chars in $attr";
      $_[0]->{$attr} = $_[1];
      undef $_[0]->{'_' . $attr};
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
      $_[0]->{_auth}{$attr} = $_[1];
      $_[0]->_reauth;
    }

    $_[0]->{_auth}{$attr};
  };
}

# Parses auth section
sub _auth {
  my ($self) = @_;
  $self->{_auth} = {}; # Set a flag to prevent reparsing
  @{ $self->{_auth} }{qw(usr pwd host port)} = auth_split($self->{auth});
  #$self->{_auth}{usr} = uri_decode($self->{_auth}{usr}) if $self->{_auth}{usr};
  #$self->{_auth}{pwd} = uri_decode($self->{_auth}{pwd}) if $self->{_auth}{pwd};
}

# Regenerates auth section
sub _reauth {
  my $self = shift;
  $self->{auth} = '';

  if ($self->{_auth}{usr}) {                         # Add the credentials block (usr:pwd)
    $self->{auth} = uri_encode($self->{_auth}{usr}); # Add user

    if ($self->{_auth}{pwd}) {                       # Add :pwd if pwd present
      $self->{auth} .= ':' . uri_encode($self->{_auth}{pwd});
    }

    $self->{auth} .= '@';
  }

  if ($self->{_auth}{host}) {
    $self->{auth} .= $self->{_auth}{host};           # Add host if present (may not be for, e.g. file://)

    if ($self->{_auth}{port}) {
      $self->{auth} .= ':' . $self->{_auth}{port};   # Port only valid if host is present
    }
  }
}

sub param {
  my ($self, $key, $val) = @_;
  $self->{query} // $val // return;

  $key = uri_encode($key);

  if ($val) {
    # Wipe out any current values for $key
    $self->{query} =~ s/&?\b$key=[^&#]+//;

    # Encode and attach values for param to query string
    foreach (ref $val ? @$val : ($val)) {
      $self->{query} .= '&' if length $self->{query};
      $self->{query} .= $key . '=' . uri_encode($_);
    }
  }

  # Collect and decode values for $key
  my @vals = $self->{query} =~ /\b$key=([^&#]+)/g;

  if (@vals) {
    if (@vals > 1) {
      return map{ tr/+/ /; uri_decode($_) } @vals;
    }
    else {
      $vals[0] =~ tr/+/ /;
      return uri_decode($vals[0]);
    }
  }
  else {
    return;
  }
}

1;

__DATA__
__C__

#include <string.h>
#
void _decode(SV* str) {
  SV* result;

  dSP;

  ENTER;
  SAVETMPS;
  PUSHMARK(SP);
  XPUSHs(str);
  PUTBACK;

  call_pv("URI::Encode::XS::uri_decode", G_SCALAR);

  SPAGAIN;

  result = POPs;
  sv_setsv(str, result);

  PUTBACK;
  FREETMPS;
  LEAVE;
}

void uri_split(SV* uri) {
  STRLEN  len;
  char*   src = SvPV(uri, len);
  size_t  idx = 0;
  size_t  brk = 0;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  // Scheme
  brk = strcspn(&src[idx], ":/@?#");
  if (brk > 0 && strncmp(&src[idx + brk], "://", 3) == 0) {
    Inline_Stack_Push(newSVpv(&src[idx], brk));
    idx += brk + 3;

    // Authority
    brk = strcspn(&src[idx], "/?#");
    if (brk > 0) {
      Inline_Stack_Push(newSVpv(&src[idx], brk));
      idx += brk;
    } else {
      Inline_Stack_Push(newSVpv("",0));
    }
  }
  else {
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
  }

  // Path
  brk = strcspn(&src[idx], "?#");
  if (brk > 0) {
    Inline_Stack_Push(newSVpv(&src[idx], brk));
    idx += brk;
  } else {
    Inline_Stack_Push(newSVpv("",0));
  }

  // Query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strcspn(&src[idx], "#");
    if (brk > 0) {
      Inline_Stack_Push(newSVpv(&src[idx], brk));
      idx += brk;
    } else {
      Inline_Stack_Push(&PL_sv_undef);
    }
  } else {
    Inline_Stack_Push(&PL_sv_undef);
  }

  // Fragment
  if (src[idx] == '#') {
    ++idx; // skip past #
    brk = len - idx;
    if (brk > 0) {
      Inline_Stack_Push(newSVpv(&src[idx], brk));
    } else {
      Inline_Stack_Push(&PL_sv_undef);
    }
  } else {
    Inline_Stack_Push(&PL_sv_undef);
  }

  Inline_Stack_Done;
}

void auth_split(SV* auth) {
  STRLEN  len;
  char*   src  = SvPV(auth, len);
  size_t  idx  = 0;
  size_t  brk1 = 0;
  size_t  brk2 = 0;

  SV* usr;
  SV* pwd;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  if (len == 0) {
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
  }
  else {
    // Credentials
    brk1 = strcspn(&src[idx], "@");

    if (brk1 > 0 && brk1 != len) {
      brk2 = strcspn(&src[idx], ":");

      if (brk2 > 0 && brk2 < brk1) {
        //Inline_Stack_Push(newSVpv(&src[idx], brk2));
        usr = newSVpv(&src[idx], brk2);
        _decode(usr);
        Inline_Stack_Push(usr);

        idx += brk2 + 1;

        //Inline_Stack_Push(newSVpv(&src[idx], brk1 - brk2 - 1));
        pwd = newSVpv(&src[idx], brk1 - brk2 - 1);
        _decode(pwd);
        Inline_Stack_Push(pwd);

        idx += brk1 - brk2;
      }
      else {
        Inline_Stack_Push(newSVpv(&src[idx], brk1));
        Inline_Stack_Push(&PL_sv_undef);
        idx += brk1 + 1;
      }
    }
    else {
      Inline_Stack_Push(&PL_sv_undef);
      Inline_Stack_Push(&PL_sv_undef);
    }

    // Location
    brk1 = strcspn(&src[idx], ":");

    if (brk1 > 0 && brk1 != (len - idx)) {
      Inline_Stack_Push(newSVpv(&src[idx], brk1));
      idx += brk1 + 1;
      Inline_Stack_Push(newSVpv(&src[idx], len - idx));
    }
    else {
      Inline_Stack_Push(newSVpv(&src[idx], len - idx));
      Inline_Stack_Push(&PL_sv_undef);
    }
  }

  Inline_Stack_Done;
}

void query_split(SV* query) {
  STRLEN  len;
  char*   src = SvPV(query, len);
  size_t  idx = 0;
  size_t  brk = 0;
  AV*     parts;
  SV*     tmp;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  parts = newAV();

  while (idx < len) {
    brk = strcspn(&src[idx], "&=");

    if (brk == 0) {
      break;
    }

    tmp = newSVpv(&src[idx], brk);
    _decode(tmp);

    av_push(parts, tmp);

    idx += brk + 1;
  }

  Inline_Stack_Push(newRV_noinc((SV*) parts));
  Inline_Stack_Done;
}
