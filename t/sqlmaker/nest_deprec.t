use strict;
use warnings;

use Test::More;
use Test::Warn;

use lib qw(t/lib);
use DBIC::SqlMakerTest;

use_ok('DBICTest');

my $schema = DBICTest->init_schema();

my $sql_maker = $schema->storage->sql_maker;

# a loop so that the callsite line does not change
for my $expect_warn (1, 0) {
  warnings_like (
    sub {
      my ($sql, @bind) = $sql_maker->select ('foo', undef, { -nest => \ 'bar' } );
      is_same_sql_bind (
        $sql, \@bind,
        'SELECT * FROM foo WHERE ( bar )', [],
        '-nest still works'
      );
    },
    ($expect_warn ? qr/\Q-nest in search conditions is deprecated/ : []),
    'Only one deprecation warning'
  );
}

done_testing;
