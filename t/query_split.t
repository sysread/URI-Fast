use Test2;
use Test2::Bundle::Extended;
use URI::Fast qw(query_split);

is query_split('a=b&c=d'), [qw(a b c d)], 'simple';
is query_split('foo=bar%20baz%20bat&word=fnord'), ['foo', 'bar baz bat', 'word', 'fnord'], 'decoding';

done_testing;
