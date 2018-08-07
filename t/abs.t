use utf8;
use ExtUtils::testlib;
use Test2::V0;
use URI::Fast qw(uri);

my $base = uri 'http://example.com/base/path?q';

my $rel = uri;

$rel->path('rel');
is $rel->abs($base), 'http://example.com/base/path/rel', 'rel';

$rel->path('./rel');
is $rel->abs($base), 'http://example.com/base/path/rel', './rel';

$rel->path('rel/');
is $rel->abs($base), 'http://example.com/base/path/rel/', 'rel/';

$rel->path('/rel');
is $rel->abs($base), 'http://example.com/rel', '/rel';

=cut
http://a/b/c/d;p?q

"g"       -> "http://a/b/c/g"
"./g"     -> "http://a/b/c/g"
"g/"      -> "http://a/b/c/g/"

"/g"      -> "http://a/g"

"//g"     -> "http://g"

"?y"      -> "http://a/b/c/d;p?y"
"g?y"     -> "http://a/b/c/g?y"
"#s"      -> "http://a/b/c/d;p?q#s"
"g#s"     -> "http://a/b/c/g#s"
"g?y#s"   -> "http://a/b/c/g?y#s"
";x"      -> "http://a/b/c/;x"
"g;x"     -> "http://a/b/c/g;x"
"g;x?y#s" -> "http://a/b/c/g;x?y#s"
""        -> "http://a/b/c/d;p?q"
"."       -> "http://a/b/c/"
"./"      -> "http://a/b/c/"
".."      -> "http://a/b/"
"../"     -> "http://a/b/"
"../g"    -> "http://a/b/g"
"../.."   -> "http://a/"
"../../"  -> "http://a/"
"../../g" -> "http://a/g"
=cut

done_testing;
