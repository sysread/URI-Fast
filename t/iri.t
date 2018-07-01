use utf8;
use ExtUtils::testlib;
use Test2::V0;
use URI::Fast qw(iri);

my $host = 'www.çæ∂î∫∫å.com';
my $path = '/ƒø∫∂é®';
my $frag = 'ƒ®å©';
my $foo  = 'ƒøø';
my $bar  = 'ßå®';
my $baz  = 'ßåΩ';
my $bat  = 'ßå†';

my $iri_str = "http://$host$path?$foo=$bar#$frag";

diag $iri_str;

# DEBUG
diag "\n";
diag '--------------------------------------------------------------------------------';
diag 'Length: ' . length($iri_str);
my $iri = iri($iri_str);
diag '--------------------------------------------------------------------------------';
$iri->debug;
diag '--------------------------------------------------------------------------------';

ok $iri, 'ctor';
ok $iri->isa('URI::Fast::IRI'), 'isa';

subtest 'getters' => sub{
  is $iri->host, $host, 'host';
  is $iri->path, $path, 'path';
  is $iri->frag, $frag, 'frag';

  is $iri->query_hash, {$foo => [$bar]}, 'query_hash';
  is [sort $iri->query_keys], [$foo], 'query_keys';
  is $iri->param($foo), $bar, 'get param';

  is "$iri", $iri_str, 'to_string';
};

subtest 'setters' => sub{
  is $iri->param($baz, $bat), $bat, 'set param';
  is $iri->param($baz), $bat, 'get param';
  is [sort $iri->query_keys], [$baz, $foo], 'query_keys';

  is $iri->host($host), $host, 'set host';
  is $iri->path($path), $path, 'set path';
  is $iri->frag($frag), $frag, 'set frag';

  is $iri->host, $host, 'host';
  is $iri->path, $path, 'path';
  is $iri->frag, $frag, 'frag';
};

subtest 'debug: append end char' => sub{
  my $iri_str = "http://$host$path?$foo=$bar#$frag" . "ƒ";
  my $iri = iri($iri_str);
  $iri->debug;
  is $iri->frag, $frag . "ƒ", 'frag';
};

subtest 'debug: replace end char' => sub{
  my $iri_str = "http://$host$path?$foo=$bar#ƒ®åƒ";
  my $iri = iri($iri_str);
  $iri->debug;
  is $iri->frag, "ƒ®åƒ", 'frag';
};

subtest 'debug: manually flip utf8 on' => sub{
  my $iri_str = "http://$host$path?$foo=$bar#$frag";
  utf8::upgrade($iri_str);
  my $iri = iri($iri_str);
  $iri->debug;
  is $iri->frag, $frag, 'frag';
};

done_testing;
