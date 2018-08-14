#!perl

BEGIN{
  unless ($ENV{BENCH} || $ENV{UPDATEBENCH}) {
    print "Skipping benchmarks because neither BENCH nor UPDATEBENCH were set.\n";
    exit 0;
  }
};

use strict;
use warnings;
use utf8;
use Benchmark qw(:all);
use Config;
use URI::Fast qw(uri uri_split iri);
use URI::Encode::XS qw();
use URI::Escape qw();
use URL::Encode qw();
use URI::Split qw();
use URI;
use IRI;

my $POD;
my $STR = '';
my $COUNT = $ENV{COUNT} || 500_000;

if ($ENV{UPDATEBENCH} ) {
  print "Updating URI::Fast::Benchmarks\n";
  open $POD, '>', './lib/URI/Fast/Benchmarks.pod' or die $!;
} else {
  print "Running benchmarks\n";
  open $POD, '>', \$STR or die $!;
}

print $POD q{=head1 NAME

URI::Fast::Benchmarks - comparing URI::Fast to other modules

=head1 DESCRIPTION

Various operations comparing L<URI::Fast> with other modules' performance.

};

my @urls = (
  '/foo/bar/baz',
  'http://www.test.com',
  'https://test.com/some/path?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
  'https://www.çæ∂î∫∫å.com/ƒø∫∂é®?ƒøø=ßå®#ƒ®å©',
);

my $encode_input = "Ῥόδος¢€" . q{! * ' ( ) ; : @ & = + $ , / ? # [ ] %} x 10;
my $decode_input = URI::Fast::encode($encode_input);

sub test {
  my ($msg, $count, $tests) = @_;
  local $| = 1;

  print "> $msg\n";
  my $results = cmpthese $count, $tests;

  print $POD "=head2 $msg\n\n";

  foreach (@$results) {
    my $fmt = '  ' . ('%15s' x scalar(@$_)) . "\n";
    printf $POD $fmt, @$_;
  }

  print $POD "\n\n";

  print "\n";
}

test 'Constructor', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]) },
  'URI::Fast' => sub{ my $uri = uri $urls[3] },
};

test 'Get scheme', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); $uri->scheme },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; $uri->scheme },
};

test 'Set scheme', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[1]); $uri->scheme('https') },
  'URI::Fast' => sub{ my $uri = uri $urls[1]; $uri->scheme('https') },
};

test 'Get authority', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); $uri->host },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; $uri->host },
};

test 'Set authority', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); $uri->host('test.com') },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; $uri->host('test.com') },
};

test 'Get path (scalar)', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); my $p = $uri->path },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; my $p = $uri->path },
};

test 'Get path (list)', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); my @p = $uri->path_segments },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; my @p = $uri->path },
};

test 'Set path (scalar)', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); $uri->path('/foo/bar') },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; $uri->path('/foo/bar') },
};

test 'Set path (array)', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); $uri->path('/' . join('/', 'foo', 'bar')) },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; $uri->path(['foo', 'bar']) },
};

test 'Get query', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); my %q = $uri->query_form },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; my @v = $uri->param('asdf') },
};

test 'Set query parameter', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); $uri->query_form(foo => 'bar') },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; $uri->param('foo', 'bar') },
};

test 'Get query (hash)', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); my %q = $uri->query_form },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; my $q = $uri->query_hash },
};

test 'Get query keys', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); my %q = $uri->query_form; my @k = keys %q; },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; my @k = $uri->query_keys },
};

test 'Stringification', $COUNT, {
  'URI' => sub{ my $uri = URI->new($urls[3]); my $str = "$uri" },
  'URI::Fast' => sub{ my $uri = uri $urls[3]; my $str = "$uri" },
};

test 'Build relative path', ($COUNT / 5), {
  'URI' => sub{ my $uri = URI->new('http://www.example.com/foo')->rel('http://www.example.com/foo/bar/') },
  'URI::Fast' => sub{ my $uri = uri('http://www.example.com/foo')->relative('http://www.example.com/foo/bar/') },
};

test 'Build absolute path', $COUNT, {
  'URI' => sub{ my $uri = URI->new('some/path')->abs('http://www.example.com/fnord') },
  'URI::Fast' => sub{ my $uri = uri('some/path')->absolute('http://www.example.com/fnord') },
};

test 'Normalize (canonical)', $COUNT, {
  'URI' => sub{ my $uri = URI->new('HTTP://EXAMPLE.com?%21%40%23%24%3D%3D%3Dhow%20now%20brown%20bureaucrat%3D%3D%3D%21%40%23%24')->canonical },
  'URI::Fast' => sub{ my $uri = uri('HTTP://EXAMPLE.com?%21%40%23%24%3D%3D%3Dhow%20now%20brown%20bureaucrat%3D%3D%3D%21%40%23%24')->normalize },
};

test 'uri_split', $COUNT, {
  'URI::Split' => sub{ my @uri = URI::Split::uri_split($urls[3]) },
  'URI::Split' => sub{ my @uri = URI::Split::uri_split($urls[3]) },
  'URI::Fast' => sub{ my @uri = uri_split($urls[3]) },
};

if ($ENV{BENCH_ALL} || $ENV{UPDATEBENCH}) {
  test 'Encode', $COUNT, {
    'URI::Escape' => sub{ URI::Escape::uri_escape_utf8($encode_input) },
    'URL::Encode' => sub{ URL::Encode::url_encode_utf8($encode_input) },
    'URI::Encode::XS' => sub{ URI::Encode::XS::uri_encode_utf8($encode_input) },
    'URI::Fast' => sub{ URI::Fast::encode($encode_input) },
  };

  test 'Decode', $COUNT, {
    'URI::Escape' => sub{ URI::Escape::uri_unescape($decode_input) },
    'URL::Encode' => sub{ URL::Encode::url_decode_utf8($decode_input) },
    'URI::Encode::XS' => sub{ URI::Encode::XS::uri_decode_utf8($decode_input) },
    'URI::Fast' => sub{ URI::Fast::decode($decode_input) },
  };

  test 'IRI - ctor', $COUNT, {
    'IRI'       => sub{ my $iri = IRI->new($urls[4]) },
    'URI::Fast' => sub{ my $iri = iri $urls[4] },
  };

  test 'IRI - set query (hash)', $COUNT, {
    'IRI' => sub{ my $iri = IRI->new($urls[4]); my %q = $iri->query_form },
    'URI::Fast' => sub{ my $iri = iri $urls[4]; my $q = $iri->query_hash },
  };

  test 'IRI - set param', $COUNT, {
    'IRI' => sub{ my $iri = IRI->new($urls[4]); $iri->query_form('ßåΩ' => 'ßå†') },
    'URI::Fast' => sub{ my $iri = iri $urls[4]; $iri->param('ßåΩ', 'ßå†') },
  };

  test 'IRI - set path', $COUNT, {
    'IRI' => sub{ my $iri = IRI->new($urls[4]); $iri->path('/Ῥόδος¢€') },
    'URI::Fast' => sub{ my $iri = iri $urls[4]; $iri->path('/Ῥόδος¢€') },
  };
}
else {
  print "Skipping time consuming benchmarks because BENCH_ALL nor UPDATEBENCH were specified.\n";
}

my $perl = Config::myconfig();
$perl =~ s/^\s+//;                       # left trim
$perl =~ s/\s+$//;                       # right trim
$perl =~ s/^/  /gsm;                     # indent lines
$perl =~ s|/home/[^/]+/|/home/user/|gsm; # anonymize personal directories

print $POD qq{

=head1 SOFTWARE VERSIONS

=over

=item URI::Fast $URI::Fast::VERSION

=item URI $URI::VERSION

=item URI::Split $URI::Split::VERSION

=item URL::Encode $URL::Encode::VERSION

=item URI::Escape $URI::Escape::VERSION

=item URI::Encode::XS $URI::Encode::XS::VERSION

=item IRI $IRI::VERSION

=back

=head1 PERL

$perl

=cut
};

close $POD;
