use utf8;
use Test2::V0;
use Test::LeakTrace qw(no_leaks_ok);
use URI::Encode::XS qw(uri_encode_utf8 uri_decode_utf8);
use URI::Fast qw(uri uri_split);
use URI::Split qw();

my @uris = (
  '/foo/bar/baz',
  'http://www.test.com',
  'https://test.com/some/path?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
);

subtest 'implicit file path' => sub{
  ok my $uri = uri($uris[0]), 'ctor';
  is $uri->scheme, 'file', 'scheme';
  ok !$uri->auth, 'auth';
  is $uri->path, '/foo/bar/baz', 'path';
  is [$uri->path], ['foo', 'bar', 'baz'], 'path';
  ok !$uri->query, 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  ok !$uri->host, 'host';
  ok !$uri->port, 'port';
};

subtest 'simple' => sub{
  ok my $uri = uri($uris[1]), 'ctor';
  is $uri->scheme, 'http', 'scheme';
  is $uri->auth, 'www.test.com', 'auth';
  ok !$uri->path, 'path';
  is [$uri->path], [], 'path';
  ok !$uri->query, 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  is $uri->host, 'www.test.com', 'host';
  ok !$uri->port, 'port';
};

subtest 'complete' => sub{
  ok my $uri = uri($uris[3]), 'ctor';
  is $uri->scheme, 'https', 'scheme';
  is $uri->auth, 'user:pwd@192.168.0.1:8000', 'auth';
  is $uri->path, '/foo/bar', 'path';
  is [$uri->path], ['foo', 'bar'], 'path';
  is $uri->query, 'baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound', 'query';
  is $uri->frag, 'foofrag', 'frag';

  is $uri->usr, 'user', 'usr';
  is $uri->pwd, 'pwd', 'pwd';
  is $uri->host, '192.168.0.1', 'host';
  is $uri->port, '8000', 'port';

  is $uri->param('baz'), 'bat', 'param';
  is $uri->param('slack'), 'fnord', 'param';
  is $uri->param('asdf'), 'the quick brown fox & hound', 'param';
};

subtest 'update auth' => sub{
  ok my $uri = uri($uris[1]), 'ctor';
  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  ok !$uri->port, 'port';

  is $uri->pwd('secret'), 'secret', 'pwd(v)';
  is $uri->auth, 'www.test.com', 'auth';
  is "$uri", 'http://www.test.com', 'string';

  is $uri->usr('someone'), 'someone', 'usr(v)';
  is $uri->auth, 'someone:secret@www.test.com', 'auth';
  is "$uri", 'http://someone:secret@www.test.com', 'string';

  is $uri->port(1234), 1234, 'port(v)';
  is $uri->auth, 'someone:secret@www.test.com:1234', 'auth';
  is "$uri", 'http://someone:secret@www.test.com:1234', 'string';

  is $uri->auth('www.nottest.com'), 'www.nottest.com', 'auth(new)';
  is $uri->host, 'www.nottest.com', 'host';
  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  ok !$uri->port, 'port';
};

subtest 'update path' => sub{
  ok my $uri = uri($uris[2]), 'ctor';
  is $uri->path, '/some/path', 'scalar path';
  is [$uri->path], ['some', 'path'], 'list path';

  is $uri->path('/foo/bar'), '/foo/bar', 'scalar path(str)';
  is "$uri", 'https://test.com/foo/bar?aaaa=bbbb&cccc=dddd&eeee=ffff', 'string';

  is [$uri->path(['baz', 'bat'])], ['baz', 'bat'], 'scalar path(list)';
  is "$uri", 'https://test.com/baz/bat?aaaa=bbbb&cccc=dddd&eeee=ffff', 'string';
};

subtest 'query' => sub{
  ok my $uri = uri($uris[2]), 'ctor';

  is $uri->param('aaaa'), 'bbbb', 'param';
  is $uri->param('cccc'), 'dddd', 'param';
  is $uri->param('eeee'), 'ffff', 'param';
  is $uri->param('fnord'), U, '!param';
  is $uri->query_hash, {aaaa => ['bbbb'], cccc => ['dddd'], eeee => ['ffff']}, 'query_hash';

  ok $uri->query({foo => 'bar', baz => 'bat'}), 'query(\%)';
  is $uri->param('foo'), 'bar', 'param';
  is $uri->param('baz'), 'bat', 'param';
  is [sort $uri->query_keys], [sort qw(foo baz)], 'query_keys';
  is $uri->query_hash, {foo => ['bar'], baz => ['bat']}, 'query_hash';

  ok !$uri->param('foo', undef), 'unset';
  is [$uri->query_keys], ['baz'], 'query_keys';
  is $uri->query_hash, {baz => ['bat']}, 'query_hash';

  is $uri->query('asdf=qwerty&asdf=fnord'), 'asdf=qwerty&asdf=fnord', 'query($)';
  is $uri->param('asdf'), ['qwerty', 'fnord'], 'param';
  is $uri->query_hash, {asdf => ['qwerty', 'fnord']}, 'query_hash';

  is [$uri->query_keys], ['asdf'], 'query_keys', "$uri";

  $uri->query('foo=barbar&bazbaz=bat&foo=blah');
  is $uri->query_hash, {foo => ['barbar', 'blah'], bazbaz => ['bat']}, 'query_hash';
};

subtest 'uri_split' => sub{
  my @uris = (
    '/foo/bar/baz',
    'file:///foo/bar/baz',
    'http://www.test.com',
    'http://www.test.com?foo=bar',
    'http://www.test.com#bar',
    'http://www.test.com/some/path',
    'https://test.com/some/path?aaaa=bbbb&cccc=dddd&eeee=ffff',
    'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
    'https://user:pwd@www.test.com:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
  );

  # From URI::Split's test suite
  subtest 'equivalence' => sub{
    is [uri_split('p')],           [U, U, 'p', U, U],          'p';
    is [uri_split('p?q')],         [U, U, 'p', 'q', U],        'p?q';
    is [uri_split('p?q/#f/?')],    [U, U, 'p', 'q/', 'f/?'],   'p?q/f/?';
    is [uri_split('s://a/p?q#f')], ['s', 'a', '/p', 'q', 'f'], 's://a/p?qf';
  };

  # Ensure identical output to URI::Split
  subtest 'parity' => sub{
    my $i = 0;
    foreach my $uri (@uris) {
      my $orig = [URI::Split::uri_split($uri)];
      my $xs   = [uri_split($uri)];
      is $xs, $orig, "uris[$i]", {orig => $orig, xs => $xs};
      ++$i;
    }
  };
};

subtest 'memory leaks' => sub{
  no_leaks_ok { my $s = URI::Fast::encode('foo') } 'encode: no memory leaks';
  no_leaks_ok { my $s = URI::Fast::decode('foo') } 'decode: no memory leaks';

  no_leaks_ok { my @parts = uri_split($uris[3]) } 'uri_split';

  no_leaks_ok { my $uri = uri($uris[3]) } 'ctor';

  my $uri = uri $uris[3];

  foreach my $acc (qw(scheme auth path query frag usr pwd host port)) {
    no_leaks_ok { $uri->$acc() } "getter: $acc";
    no_leaks_ok { $uri->$acc("foo") } "setter: $acc";
  }

  no_leaks_ok { my @parts = $uri->path } 'split path';
  no_leaks_ok { $uri->param('foo', 'bar') } 'param';
  no_leaks_ok { $uri->param('foo', ['bar', 'baz']) } 'param';
  no_leaks_ok { $uri->query_keys } 'query_keys';
  no_leaks_ok { $uri->query_hash } 'query_hash';
  no_leaks_ok { $uri->to_string } 'to_string';
};

done_testing;
