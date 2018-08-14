#!perl

BEGIN{
  unless ($ENV{BENCH}) {
    print "Skipping internals benchmarks because BENCH was not set.\n";
    exit 0;
  }
};

use URI::Fast qw(uri uri_split);
use Benchmark qw(:all);
use URI;

my $url     = 'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&baz=bar&asdf=the+quick%20brown+fox+%26+hound#foofrag';
my $uri     = uri($url);
my $decoded = "Ῥόδος";
my $encoded = '%E1%BF%AC%CF%8C%CE%B4%CE%BF%CF%82';

print "\nGeneral:\n\n";
timethese 1_000_000, {
  'ctor               ' => sub{ my $u = uri $url },
  'stringification    ' => sub{ my $u = $uri->to_string },
  'uri_split          ' => sub{ my @u = $uri->to_string },
};

print "\nGetters:\n\n";
timethese 2_000_000, {
  'get: raw           ' => sub{ my $u = $uri->raw_scheme },
  'get: simple        ' => sub{ my $u = $uri->scheme },
  'get: compound      ' => sub{ my $u = $uri->host },
};

print "\nSetters:\n\n";
timethese 2_000_000, {
  'set: simple        ' => sub{ $uri->scheme('http') },
  'set: compound      ' => sub{ $uri->host('www.test.com') },
};

print "\nQuery:\n\n";
timethese 1_000_000, {
  'query_hash         ' => sub{ my $u = $uri->query_hash },
  'query_keys         ' => sub{ my @u = $uri->query_keys },
  'get: param (scalar)' => sub{ my $u = $uri->param('slack') },
  'set: param (scalar)' => sub{ my $u = $uri->param('foo', 'bar') },
  'get: param (list)  ' => sub{ my @u = $uri->param('baz') },
  'set: param (list)  ' => sub{ my @u = $uri->param('foo', ['bar', 'baz']) },
};

print "\nPath:\n\n";
timethese 1_000_000, {
  'get: path (scalar) ' => sub{ my $u = scalar($uri->path) },
  'set: path (scalar) ' => sub{ $uri->path('/foo/bar') },
  'get: path (list)   ' => sub{ my @u = $uri->path },
  'set: path (list)   ' => sub{ $uri->path(['foo', 'bar']) },
};

print "\nEncoding:\n\n";
timethese 5_000_000, {
  'encode ' => sub{ URI::Fast::encode($decoded) },
  'decode ' => sub{ URI::Fast::decode($encoded) },
};

print "\n";
