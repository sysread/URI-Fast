use utf8;
use ExtUtils::testlib;
use Test2::V0;
use URI::Fast qw(uri);

my $base = 'http://a/b/c/d;p?q';

my @tests = (
  ["g"       , "http://a/b/c/g"],
  ["./g"     , "http://a/b/c/g"],
  ["g/"      , "http://a/b/c/g/"],
  ["/g"      , "http://a/g"],
  ["//g"     , "http://g"],
  ["?y"      , "http://a/b/c/d;p?y"],
  ["g?y"     , "http://a/b/c/g?y"],
  ["#s"      , "http://a/b/c/d;p?q#s"],
  ["g#s"     , "http://a/b/c/g#s"],
  ["g?y#s"   , "http://a/b/c/g?y#s"],
  [";x"      , "http://a/b/c/;x"],
  ["g;x"     , "http://a/b/c/g;x"],
  ["g;x?y#s" , "http://a/b/c/g;x?y#s"],
  [""        , "http://a/b/c/d;p?q"],
  ["."       , "http://a/b/c/"],
  ["./"      , "http://a/b/c/"],
  [".."      , "http://a/b/"],
  ["../"     , "http://a/b/"],
  ["../g"    , "http://a/b/g"],
  ["../.."   , "http://a/"],
  ["../../"  , "http://a/"],
  ["../../g" , "http://a/g"],
);

foreach my $test (@tests) {
  my ($rel, $exp) = @$test;
  my $abs = uri($rel)->absolute(uri($base));
  is $abs, $exp, "abs: $rel -> $exp"
    or do{
      diag "rel:    '$rel'";
      diag "base:   '$base'";
      diag "exp:    '$exp'";
      diag "actual: '$abs'";
    };
}

done_testing;
