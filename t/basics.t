use Test2;
use Test2::Bundle::Extended;

use URI::Fast qw(uri);

my @urls = (
  '/foo/bar/baz',
  'http://www.test.com',
  'https://test.com/some/path?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://test.com/some/path/?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
);

subtest 'implicit file path' => sub{
  ok my $uri = uri($urls[0]), 'ctor';
  is $uri->scheme, 'file', 'scheme';
  ok !$uri->auth, 'auth';
  is $uri->path, '/foo/bar/baz', 'path';
  is [$uri->split_path], ['foo', 'bar', 'baz'], 'split_path';
  ok !$uri->query, 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  ok !$uri->host, 'host';
  ok !$uri->port, 'port';
};

subtest 'simple' => sub{
  ok my $uri = uri($urls[1]), 'ctor';
  is $uri->scheme, 'http', 'scheme';
  is $uri->auth, 'www.test.com', 'auth';
  ok !$uri->path, 'path';
  is [$uri->split_path], [], 'split_path';
  ok !$uri->query, 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  is $uri->host, 'www.test.com', 'host';
  ok !$uri->port, 'port';
};

subtest 'path & query' => sub{
  ok my $uri = uri($urls[2]), 'ctor';
  is $uri->scheme, 'https', 'scheme';
  is $uri->auth, 'test.com', 'auth';
  is $uri->path, '/some/path', 'path';
  is [$uri->split_path], ['some', 'path'], 'split_path';
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
    ok my $uri = uri($urls[3]), 'ctor';
    is $uri->scheme, 'https', 'scheme';
    is $uri->auth, 'test.com', 'auth';
    is $uri->path, '/some/path', 'path';
    is [$uri->split_path], ['some', 'path'], 'split_path';
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
  ok my $uri = uri($urls[4]), 'ctor';
  is $uri->scheme, 'https', 'scheme';
  is $uri->auth, 'user:pwd@192.168.0.1:8000', 'auth';
  is $uri->path, '/foo/bar', 'path';
  is [$uri->split_path], ['foo', 'bar'], 'split_path';
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

done_testing;
