use utf8;
use Test2::V0;
use Test::LeakTrace qw(no_leaks_ok);
use URI::Encode::XS qw();
use URI::Fast qw(uri uri_split);
use URI::Split qw();

my @uris = (
  '/foo/bar/baz',
  'http://www.test.com',
  'https://test.com/some/path?aaaa=bbbb&cccc=dddd&eeee=ffff',
  'https://user:pwd@192.168.0.1:8000/foo/bar?baz=bat&slack=fnord&asdf=the+quick%20brown+fox+%26+hound#foofrag',
);

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

subtest 'percent encoding' => sub{
  my $reserved = q{! * ' ( ) ; : @ & = + $ , / ? # [ ] %};
  my $utf8 = "Ῥόδος¢€";

  is URI::Fast::encode_reserved('asdf', ''), 'asdf', 'non-reserved';

  foreach (split ' ', $reserved) {
    is URI::Fast::encode_reserved($_, ''), sprintf('%%%02X', ord($_)), "reserved char $_";
  }

  is URI::Fast::encode("$reserved $utf8", ''), URI::Encode::XS::uri_encode_utf8("$reserved $utf8"), "utf8 + reserved";

  my $str = URI::Fast::encode($reserved, '');
  is URI::Fast::decode($str), $reserved, 'decode';
};

subtest 'utf8' => sub{
  my $u = "Ῥόδος";
  my $a = '%E1%BF%AC%CF%8C%CE%B4%CE%BF%CF%82';

  is URI::Fast::encode_utf8('$'), '$', '1 byte';
  is URI::Fast::encode_utf8('¢'), URI::Encode::XS::uri_encode_utf8('¢'), 'encode_utf8: 2 bytes';
  is URI::Fast::encode_utf8('€'), URI::Encode::XS::uri_encode_utf8('€'), 'encode_utf8: 3 bytes';
  is URI::Fast::encode_utf8('􏿿'), URI::Encode::XS::uri_encode_utf8('􏿿'), 'encode_utf8: 4 bytes';
  is URI::Fast::encode_utf8($u), $a, 'encode_utf8: string';

  is URI::Fast::encode($u, ''), $a, 'encode';
  is URI::Fast::decode($a), $u, 'decode';

  ok my $uri = uri($uris[2]), 'ctor';

  is $uri->auth("$u:$u\@www.$u.com:1234"), "$a:$a\@www.$a.com:1234", 'auth';

  is $uri->usr, $u, 'usr';
  is $uri->pwd, $u, 'pwd';
  is $uri->host, "www.$u.com", 'host';

  is $uri->path("/$u/$u"), "/$u/$u", "path";
  is $uri->path([$u, $a]), "/$u/$a", "path";

  is $uri->query("x=$a"), "x=$a", "query";
  is $uri->param('x'), $u, 'param', $uri->get_query;
  is $uri->query({x => $u}), "x=$a", "query", $uri->get_query;
  is $uri->param('x'), $u, 'param', $uri->get_query;
};

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

subtest 'path & query' => sub{
  ok my $uri = uri($uris[2]), 'ctor';
  is $uri->scheme, 'https', 'scheme';
  is $uri->auth, 'test.com', 'auth';
  is $uri->path, '/some/path', 'path';
  is [$uri->path], ['some', 'path'], 'path';
  is $uri->query, 'aaaa=bbbb&cccc=dddd&eeee=ffff', 'query';
  ok !$uri->frag, 'frag';

  ok !$uri->usr, 'usr';
  ok !$uri->pwd, 'pwd';
  is $uri->host, 'test.com', 'host';
  ok !$uri->port, 'port';

  is $uri->param('aaaa'), 'bbbb', 'param';
  is $uri->param('cccc'), 'dddd', 'param';
  is $uri->param('eeee'), 'ffff', 'param';
  is $uri->param('fnord'), U, '!param';

  ok $uri->query({foo => 'bar', baz => 'bat'}), 'query(\%)';
  is $uri->param('foo'), 'bar', 'param';
  is $uri->param('baz'), 'bat', 'param';
  is [sort $uri->query_keys], [sort qw(foo baz)], 'query_keys';

  ok !$uri->param('foo', undef), 'unset';
  is [$uri->query_keys], ['baz'], 'query_keys';

  is $uri->query('asdf=qwerty&asdf=fnord'), 'asdf=qwerty&asdf=fnord', 'query($)';
  is $uri->param('asdf'), ['qwerty', 'fnord'], 'param';

  is [$uri->query_keys], ['asdf'], 'query_keys', "$uri";

  $uri->query('foo=barbar&bazbaz=bat&foo=blah');
  is $uri->query_hash, {foo => ['barbar', 'blah'], bazbaz => ['bat']}, 'query_hash';
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

subtest 'update param' => sub{
  ok my $uri = uri($uris[2]), 'ctor';
  is $uri->param('cccc'), 'dddd', 'param(k)';
  is $uri->param('cccc', 'qwerty'), 'qwerty', 'param(k,v)';
  is $uri->param('cccc'), 'qwerty', 'param(k)';
  is $uri->query, 'aaaa=bbbb&eeee=ffff&cccc=qwerty', 'query';
  is "$uri", 'https://test.com/some/path?aaaa=bbbb&eeee=ffff&cccc=qwerty', 'string';

  is $uri->query('foo=bar'), 'foo=bar', 'query(new)';
  is $uri->param('foo'), 'bar', 'new query parsed';
  ok !$uri->param('cccc'), 'old parsed values removed';
};

subtest 'memory leaks' => sub{
  no_leaks_ok { my $s = URI::Fast::encode('foo', '') } 'encode: no memory leaks';
  no_leaks_ok { my $s = URI::Fast::decode('foo') } 'decode: no memory leaks';
  no_leaks_ok { my @parts = uri_split($uris[3]) } 'uri_split';
  no_leaks_ok { my $uri = uri($uris[3]) } 'ctor';
  no_leaks_ok { uri($uris[3])->scheme('stuff') } 'scheme';
  no_leaks_ok { uri($uris[3])->auth('foo@www.Ῥόδος.com') } 'auth';
  no_leaks_ok { uri($uris[3])->get_param('baz') } 'get_param';
  no_leaks_ok { uri($uris[3])->param('foo', 'bar') } 'param';
  no_leaks_ok { uri($uris[3])->param('foo', ['bar', 'baz']) } 'param';
  no_leaks_ok { uri($uris[3])->query_keys } 'query_keys';
  no_leaks_ok { my @parts = uri($uris[3])->path } 'split path';
  no_leaks_ok { uri($uris[3])->path(['foo', 'bar']) } 'set path';
  no_leaks_ok { uri($uris[3])->usr('foo') } 'set usr/regen auth';
  no_leaks_ok { uri($uris[3])->to_string } 'to_string';
  no_leaks_ok { uri($uris[3])->query_hash } 'query_hash';
};

done_testing;
