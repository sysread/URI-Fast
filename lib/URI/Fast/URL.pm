package URI::Fast::URL;

use strict;
use warnings;

require URI::Fast;
our @ISA = qw(URI::Fast);

use Encode qw(encode);

sub uri {
  my ($uri_string, %param) = @_;
  my $encoding = $param{encoding} || 'UTF-8';
  my $scheme   = URI::Fast::uri( $param{scheme} )->scheme;

  # First, interpret the URI string as the encoding from the document from
  # which it presuambly came.
  $uri_string = encode $encoding, $uri_string, Encode::FB_CROAK;

  # Next, remove characters specified by the URL standard
  $uri_string =~ s|[\t\r\n]||g; # strip tabs, line feeds, and carriage returns
  $uri_string =~ s|\\|/|g;      # convert backslashes to forward slashes

  # Then, parse the URI string into a URI::Fast object
  my $uri = uri $uri_string;

  # Replace the scheme with a reference scheme, presumably from the source
  # document from which the URI was read.
  if ($scheme) {
    $uri->scheme($scheme);
  }

  return $uri;
}

1;
