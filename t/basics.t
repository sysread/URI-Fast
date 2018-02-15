use Test2;
use Test2::Bundle::Extended;

use URI::Tiny qw(uri_of_str str_of_uri);

my @urls = (
  '/foo/bar/baz',
  'http://www.test.com',
  'https://test.com/some/path?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://test.com/some/path/?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
);

subtest 'implicit file path' => sub{
  ok my $uri = uri_of_str($urls[0]), 'new';
  is $uri->scheme, 'file', 'scheme';
  ok !$uri->auth, 'auth';
  is $uri->path, '/foo/bar/baz', 'path';
  is [$uri->split_path], ['/foo', '/bar', '/baz'], 'path as array';
  ok !$uri->query, 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  ok !$uri->host, 'host';
  ok !$uri->port, 'port';
};

subtest 'simple' => sub{
  ok my $uri = uri_of_str($urls[1]), 'new';
  is $uri->scheme, 'http', 'scheme';
  is $uri->auth, 'www.test.com', 'auth';
  ok !$uri->path, 'path';
  is [$uri->split_path], [], 'path as array';
  ok !$uri->query, 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  is $uri->host, 'www.test.com', 'host';
  ok !$uri->port, 'port';
};

subtest 'path & query' => sub{
  ok my $uri = uri_of_str($urls[2]), 'new';
  is $uri->scheme, 'https', 'scheme';
  is $uri->auth, 'test.com', 'auth';
  is $uri->path, '/some/path', 'path';
  is [$uri->split_path], ['/some', '/path'], 'path as array';
  is $uri->query, 'aaaa=bbbb&cccc=dddd&eeee=ffff', 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  is $uri->host, 'test.com', 'host';
  ok !$uri->port, 'port';

  is $uri->param('aaaa'), 'bbbb', 'query';
  is $uri->param('cccc'), 'dddd', 'query';
  is $uri->param('eeee'), 'ffff', 'query';
  is $uri->param('fnord'), U, '!query';

  subtest 'path w/ trailing slash' => sub {
    ok my $uri = uri_of_str($urls[3]), 'new';
    is $uri->scheme, 'https', 'scheme';
    is $uri->auth, 'test.com', 'auth';
    is $uri->path, '/some/path', 'path';
    is [$uri->split_path], ['/some', '/path'], 'path as array';
    is $uri->query, 'aaaa=bbbb&cccc=dddd&eeee=ffff', 'query';
    ok !$uri->frag, 'frag';

    ok !$uri->usr, 'usr';
    ok !$uri->pwd, 'pwd';
    is $uri->host, 'test.com', 'host';
    ok !$uri->port, 'port';

    is $uri->param('aaaa'), 'bbbb', 'query';
    is $uri->param('cccc'), 'dddd', 'query';
    is $uri->param('eeee'), 'ffff', 'query';
    is $uri->param('fnord'), U, '!query';
  };
};

subtest 'complete' => sub{
  ok my $uri = uri_of_str($urls[4]), 'new';
  is $uri->scheme, 'https', 'scheme';
  is $uri->auth, 'user:pwd@192.168.0.1:8000', 'auth';
  is $uri->path, '/foo/bar', 'path';
  is [$uri->split_path], ['/foo', '/bar'], 'path as array';
  is $uri->query, 'baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound', 'query';
  is $uri->frag, 'foofrag', 'frag';

  is $uri->usr, 'user', 'usr';
  is $uri->pwd, 'pwd', 'pwd';
  is $uri->host, '192.168.0.1', 'host';
  is $uri->port, '8000', 'port';

  is $uri->param('baz'), 'bat', 'query';
  is $uri->param('slack'), 'fnord', 'query';
  is $uri->param('asdf'), 'the quick brown fox & hound', 'query';
};

subtest 'building' => sub{
  ok my $uri = uri_of_str($urls[1]), 'new';
  is $uri->usr('someone'), 'someone', 'set usr';
  is $uri->host('www.fnord.com'), 'www.fnord.com', 'set host';
  is $uri->auth, 'someone@www.fnord.com', 'auth correctly set';

  is $uri->usr(undef), U, 'undef usr';
  is $uri->auth, 'www.fnord.com', 'auth correctly updated';

  is $uri->query, U, 'undef query';
  is $uri->param('foo'), U, 'get undef param';
  is $uri->param('foo', 'bar'), 'bar', 'set param';
  is $uri->param('baz', 'bat'), 'bat', 'set param';
  like $uri->query, qr/foo=bar/, 'query correctly updated';
  like $uri->query, qr/baz=bat/, 'query correctly updated';
  like $uri->query, qr/&/, 'query correctly updated';
};

done_testing;
