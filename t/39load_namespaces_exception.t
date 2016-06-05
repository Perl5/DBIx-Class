BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;
use Test::More;


use DBICTest; # do not remove even though it is not used

plan tests => 1;

eval {
    package DBICNSTest;
    use base qw/DBICTest::BaseSchema/;
    __PACKAGE__->load_namespaces(
        result_namespace => 'Bogus',
        resultset_namespace => 'RSet',
    );
};

like ($@, qr/are you sure this is a real Result Class/, 'Clear exception thrown');
