use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest::init_schema();

BEGIN {
        eval "use DBD::SQLite";
        plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 3);
}                                                                               

my $art = $schema->resultset("Artist")->find(1);

isa_ok $art => 'DBICTest::Artist';

my $name = 'Caterwauler McCrae';

ok($art->name($name) eq $name, 'update');

{ 
  my @changed_keys = $art->is_changed;
  is( scalar (@changed_keys), 0, 'field changed but same value' );
}                                                                               

$art->discard_changes;

