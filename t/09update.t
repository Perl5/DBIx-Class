use strict;
use Test::More;

BEGIN {
        eval "use DBD::SQLite";
        plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 4);
}                                                                               

use lib qw(t/lib);

use_ok('DBICTest');

my $art = DBICTest::Artist->retrieve(1);

isa_ok $art => 'DBICTest::Artist';

my $name = 'Caterwauler McCrae';

ok($art->name($name) eq $name, 'update');

{ 
  my @changed_keys = $art->is_changed;
  is( scalar (@changed_keys), 0, 'field changed but same value' );
}                                                                               

$art->discard_changes;
