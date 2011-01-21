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

my $schema = DBICNSTest->connect("dbi:SQLite::memory:", "", "");
$schema->deploy;
use Data::Dumper;

warn "linear: " . Dumper mro::get_linear_isa(ref $schema->resultset('MROOrder'));
done_testing();
