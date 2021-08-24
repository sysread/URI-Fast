use Test2::V0;
use ExtUtils::testlib;
use URI::Fast qw(uri html_url);

subtest html_url => sub{
  subtest 'without base' => sub{
    my $url = html_url("//www.example.com\\foo\n\t\r\\bar");
    isa_ok $url, 'URI::Fast';
    is $url, 'www.example.com/foo/bar', 'html_url';
  };

  subtest 'with base' => sub{
    my $url = html_url("//www.example.com/foo\t\\bar\\..", "http://www.example.com/foo");
    isa_ok $url, 'URI::Fast';
    is $url, 'http://www.example.com/foo/', 'html_url';
  };
};

subtest new_html_url => sub{
  subtest 'without base' => sub{
    my $url = URI::Fast->new_html_url("//www.example.com\\foo\n\t\r\\bar");
    isa_ok $url, 'URI::Fast';
    is $url, 'www.example.com/foo/bar', 'html_url';
  };

  subtest 'with base' => sub{
    my $url = URI::Fast->new_html_url("//www.example.com/foo\t\\bar\\..", "http://www.example.com/foo");
    isa_ok $url, 'URI::Fast';
    is $url, 'http://www.example.com/foo/', 'new_html_url';
  };
};

subtest outliers => sub{
  is html_url('', 'http://xyz.com'), 'http://xyz.com', 'rel is an empty string';
};

done_testing;
