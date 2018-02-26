use Test2;
use Test2::Bundle::Extended;
use URI::Split qw();
use URI::Fast qw(auth_split);

subtest basics => sub{
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
};

subtest encoding => sub{
  my $uri = 'some%20one:secret%20password@www.test.com';
  my ($usr, $pwd, $host, $port) = auth_split $uri;
  is $usr, 'some one', 'usr';
  is $pwd, 'secret password', 'pwd';
  is $host, 'www.test.com', 'host';
  is $port, U, 'port';
};

done_testing;
