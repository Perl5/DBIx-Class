use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;


use_ok('DBICTest');
use_ok('DBIC::DebugObj');
my $schema = DBICTest->init_schema();

my ($sql, @bind);
$schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
$schema->storage->debug(1);

my $rs = $schema->resultset('BadNames1');

eval {
   $rs->create({ good_name => 2002, })
};

is_same_sql_bind(
  $sql, \@bind,
  "INSERT INTO bad_names_1( stupid_name ) VALUES ( ? )", ["'2002'"],
  'insert'
);

eval {
   $rs->search({ 'me.good_name' => 2001 })->all
};

is_same_sql_bind(
  $sql, \@bind,
  "SELECT me.id, me.stupid_name FROM bad_names_1 me WHERE ( me.stupid_name = ? )", ["'2001'"],
  'select'
);

eval {
   $rs->search({ 'me.good_name' => 2001 })->update({ good_name => 2112 })
};


is_same_sql_bind(
  $sql, \@bind,
  "UPDATE bad_names_1 SET stupid_name = ? WHERE ( stupid_name = ? )", ["'2112'", "'2001'"],
  'update'
);

eval {
   $rs->search({ 'me.good_name' => 2001 })->delete
};

is_same_sql_bind(
  $sql, \@bind,
  "DELETE FROM bad_names_1 WHERE ( me.stupid_name = ? )", ["'2001'"],
  'delete'
);

done_testing;
