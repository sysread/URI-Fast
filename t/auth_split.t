use Test2;
use Test2::Bundle::Extended;
use URI::Fast qw(auth_split);

my $usr  = 'someone';
my $pwd  = 'fnord';
my $host = 'www.test.com';
my $port = 1234;

my $tests = [
  ["$usr:$pwd\@$host:$port" => [$usr, $pwd, $host, $port]],
  ["$usr\@$host:$port"      => [$usr, U, $host, $port]],
  ["$host:$port"            => [U, U, $host, $port]],
  ["$host"                  => [U, U, $host, U]],
  [""                       => [U, U, U, U]],
];

foreach (@$tests) {
  my ($auth, $expected) = @$_;
  my $split = [auth_split($auth)];
  is $split, $expected, $auth, $split;
}

done_testing;
