use strict;
use warnings;
use Pod::Select 'podselect';

print "Generating README.pod\n";

podselect {-output => 'README.pod'}, 'lib/URI/Fast.pm';

exit 0;
