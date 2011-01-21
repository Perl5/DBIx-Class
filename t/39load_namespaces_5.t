use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces;
};
my $source_mro_order = DBICNSTest->source('MROOrder');
isa_ok($source_mro_order , 'DBIx::Class::ResultSource::Table');

done_testing();
