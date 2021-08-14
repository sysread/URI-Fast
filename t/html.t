use Test2::V0;
use ExtUtils::testlib;
use URI::Fast qw(uri html_url abs_html_url);

subtest html_url => sub{
  my $url = html_url("//www.example.com\\foo\n\t\r\\bar", "http://www.example.com");
  isa_ok $url, 'URI::Fast';
  is $url, 'http://www.example.com/foo/bar', 'html_url';
};

subtest abs_html_url => sub{
  my $url = abs_html_url("//www.example.com/foo\t\\bar\\..", "http://www.example.com/foo");
  isa_ok $url, 'URI::Fast';
  is $url, 'http://www.example.com/foo/', 'html_url';
};

done_testing;
