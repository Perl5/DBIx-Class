use strict;
use warnings;

use Test::More;
use Test::Warn;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

# This is legacy stuff from SQL::Absract::Limit
# Keep it around just in case someone is using it

{
  package DBICTest::SQLMaker::CustomDialect;
  use base qw/DBIx::Class::SQLMaker/;
  sub emulate_limit {
    my ($self, $sql, $rs_attrs, $limit, $offset) = @_;
    return sprintf ('shiny sproc ((%s), %d, %d)',
      $sql,
      $limit || 0,
      $offset || 0,
    );
  }
}
my $s = DBICTest::Schema->connect (DBICTest->_database);
$s->storage->sql_maker_class ('DBICTest::SQLMaker::CustomDialect');

my $rs = $s->resultset ('CD');

warnings_exist { is_same_sql_bind (
  $rs->search ({}, { rows => 1, offset => 3,columns => [
      { id => 'foo.id' },
      { 'artist.id' => 'bar.id' },
      { bleh => \ 'TO_CHAR (foo.womble, "blah")' },
    ]})->as_query,
  '(
    shiny sproc (
      (
        SELECT foo.id, bar.id, TO_CHAR (foo.womble, "blah")
          FROM cd me
      ),
      1,
      3
    )
  )',
  [],
  'Rownum subsel aliasing works correctly'
 )}
  qr/\Qthe legacy emulate_limit() mechanism inherited from SQL::Abstract::Limit has been deprecated/,
  'deprecation warning'
;

done_testing;
