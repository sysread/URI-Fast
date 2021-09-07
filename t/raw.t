use utf8;
use ExtUtils::testlib;
use Test2::V0;
use URI::Fast qw(uri);

my $utf8 = "Ῥόδος¢€";

my @fields = qw(
  scheme
  path
  query
  frag
  usr
  pwd
  host
  port
);

for my $field (@fields) {
  subtest "raw_$field" => sub{
    my $uri = uri;
    my $mtd = $uri->can("raw_$field");
    my $got = $uri->$mtd($utf8);
    utf8::decode($got); # will come back as raw bytes
    is $got, $utf8, "$field not encoded when get/set raw";
  };
}

subtest 'raw_auth' => sub{
  my $auth = sprintf '%s:%s@%s:%s', $utf8, $utf8, $utf8, $utf8;
  my $uri = uri;
  my $got = $uri->raw_auth($auth);
  utf8::decode($got); # will come back as raw bytes
  is $got, $auth, "auth not encoded when get/set raw";

  my $exp = $utf8;
  utf8::encode($exp);

  is $uri->raw_usr, $exp, '...sets usr raw';
  is $uri->raw_pwd, $exp, '...sets pwd raw';
  is $uri->raw_host, $exp, '...sets host raw';
  is $uri->raw_port, $exp, '...sets port raw';
};

done_testing;
