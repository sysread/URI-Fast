use utf8;
use ExtUtils::testlib;
use Test2::V0;
use URI::Fast qw(uri);

{ diag 'subtest: param'; # => sub{
  foreach my $sep (qw(& ;)) {
    { diag "subtest: separator '$sep'"; # => sub {
      my $uri = uri "http://www.test.com?foo=bar${sep}foo=baz${sep}fnord=slack";

      { diag 'subtest: context'; # => sub{
        is [$uri->param('foo')], [qw(bar baz)], 'get (list)';
        is $uri->param('fnord'), 'slack', 'get (scalar): single value as scalar';
        ok dies{ my $foo = $uri->param('foo'); }, 'get (scalar): dies when encountering multiple values';
      };

      { diag 'subtest: unset'; # => sub {
        is $uri->param('foo', undef, $sep), U, 'set';
        is $uri->param('foo'), U, 'get';
        is $uri->query, 'fnord=slack', 'updated: query';
      };

      { diag 'subtest: set: string'; # => sub {
        is $uri->param('foo', 'bar', $sep), 'bar', 'set (scalar, single value)';
        is $uri->param('foo'), 'bar', 'get';
        is $uri->query, "fnord=slack${sep}foo=bar", 'updated: query';
      };

      { diag 'subtest: set: array ref'; # => sub {
        is [$uri->param('foo', [qw(bar baz)], $sep)], [qw(bar baz)], 'set';
        is [$uri->param('foo')], [qw(bar baz)], 'get';
        is $uri->query, "fnord=slack${sep}foo=bar${sep}foo=baz", 'updated: query';
        is [$uri->param('qux', 'corge', $sep)], [qw(corge)], 'set qux';
        is [$uri->param('qux')], [qw(corge)], 'get qux';
        is $uri->query, "fnord=slack${sep}foo=bar${sep}foo=baz${sep}qux=corge", 'updated: query';
      };

      { diag 'subtest: whitespace in value'; # => sub{
        my $uri = uri;
        $uri->param('foo', 'bar baz');
        is $uri->param('foo'), 'bar baz', 'param: expected result';
        is $uri->query, 'foo=bar%20baz', 'param: expected result from query';

        $uri = uri;
        $uri->add_param('foo', 'bar baz');
        is $uri->param('foo'), 'bar baz', 'add_param: expected result from param';
        is $uri->query, 'foo=bar%20baz', 'add_param: expected result from query';
      };

      { diag 'subtest: edge cases'; # => sub {
        { diag 'subtest: empty parameter'; # => sub {
          my $uri = uri 'http://www.test.com?foo=';
          is $uri->param('foo'), '', 'expected param value';
        };

        { diag 'subtest: empty parameter w/ previous parameter parameter'; # => sub {
          my $uri = uri 'http://www.test.com?bar=baz&foo=';
          is $uri->param('foo'), '', 'expected param value';
        };

        { diag 'subtest: empty parameter w/ following parameter'; # => sub {
          my $uri = uri 'http://www.test.com?foo=&bar=baz';
          is $uri->param('foo'), '', 'expected param value';
        };

        { diag 'subtest: unset only parameter'; # => sub {
          my $uri = uri 'http://www.test.com?foo=bar';
          $uri->param('foo', undef, $sep);
          is $uri->query, '', 'expected query value';
        };

        { diag 'subtest: unset final parameter'; # => sub {
          my $uri = uri "http://www.test.com?bar=bat${sep}foo=bar";
          $uri->param('foo', undef, $sep);
          is $uri->query, 'bar=bat', 'expected query value';
        };

        { diag 'subtest: unset initial parameter'; # => sub {
          my $uri = uri "http://www.test.com?bar=bat${sep}foo=bar";
          $uri->param('bar', undef, $sep);
          is $uri->query, 'foo=bar', 'expected query value';
        };

        { diag 'subtest: update initial parameter'; # => sub {
          my $uri = uri "http://www.test.com?bar=bat${sep}foo=bar";
          $uri->param('bar', 'blah', $sep);
          is $uri->query, "foo=bar${sep}bar=blah", 'expected query value';
        };

        { diag 'subtest: update final parameter'; # => sub {
          my $uri = uri "http://www.test.com?bar=bat${sep}foo=bar";
          $uri->param('foo', 'blah', $sep);
          is $uri->query, "bar=bat${sep}foo=blah", 'expected query value';
        };
      };
    };
  }

  { diag 'subtest: separator replacement'; # => sub {
    my $uri = uri 'http://example.com';

    $uri->param('foo', 'bar');
    $uri->param('baz', 'bat');
    like $uri->query, qr/&/, 'separator defaults to &';

    $uri->param('asdf', 'qwerty', ';');
    like $uri->query, qr/;/, 'explicit separator used';
    unlike $uri->query, qr/&/, 'original separator replaced';
  };
};

{ diag 'subtest: add_param'; # => sub{
  my $uri = uri 'http://www.test.com';
  is $uri->param('foo', 'bar'), 'bar', 'param';
  is [$uri->add_param('foo', 'baz')], ['bar', 'baz'], 'add_param';
  is [$uri->param('foo')], ['bar', 'baz'], 'add_param';

  { diag 'subtest: separator replacement'; # => sub {
    my $uri = uri 'http://example.com';

    $uri->add_param('foo', 'bar');
    $uri->add_param('foo', 'baz');
    $uri->add_param('foo', 'bat');
    like $uri->query, qr/&/, 'separator defaults to &';

    $uri->add_param('asdf', 'qwerty', ';');
    like $uri->query, qr/;/, 'explicit separator used';
    unlike $uri->query, qr/&/, 'original separator replaced';
  };
};

done_testing;
