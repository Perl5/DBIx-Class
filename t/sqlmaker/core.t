use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema(no_deploy => 1);

my $sql_maker = $schema->storage->sql_maker;


{
  my ($sql, @bind) = $sql_maker->insert(
            'lottery',
            {
              'day' => '2008-11-16',
              'numbers' => [13, 21, 34, 55, 89]
            }
  );

  is_same_sql_bind(
    $sql, \@bind,
    q/INSERT INTO lottery (day, numbers) VALUES (?, ?)/,
      [ ['day' => '2008-11-16'], ['numbers' => [13, 21, 34, 55, 89]] ],
    'sql_maker passes arrayrefs in insert'
  );


  ($sql, @bind) = $sql_maker->update(
            'lottery',
            {
              'day' => '2008-11-16',
              'numbers' => [13, 21, 34, 55, 89]
            }
  );

  is_same_sql_bind(
    $sql, \@bind,
    q/UPDATE lottery SET day = ?, numbers = ?/,
      [ ['day' => '2008-11-16'], ['numbers' => [13, 21, 34, 55, 89]] ],
    'sql_maker passes arrayrefs in update'
  );
}

# make sure the cookbook caveat of { $op, \'...' } no longer applies
{
  my ($sql, @bind) = $sql_maker->where({
    last_attempt => \ '< now() - interval "12 hours"',
    next_attempt => { '<', \ 'now() - interval "12 hours"' },
    created => [
      { '<=', \ '1969' },
      \ '> 1984',
    ],
  });
  is_same_sql_bind(
    $sql,
    \@bind,
    'WHERE
          (created <= 1969 OR created > 1984 )
      AND last_attempt < now() - interval "12 hours"
      AND next_attempt < now() - interval "12 hours"
    ',
    [],
  );
}

# Tests base class for => \'FOO' actually generates proper query. for =>
# 'READ'|'SHARE' is tested in db-specific subclasses
# we have to instantiate base because SQLMaker::SQLite disables _lock_select
{
  require DBIx::Class::SQLMaker;
  my $sa = DBIx::Class::SQLMaker->new;
  {
    my ($sql, @bind) = $sa->select('foo', '*', {}, { for => 'update' } );
    is_same_sql_bind(
      $sql,
      \@bind,
      'SELECT * FROM foo FOR UPDATE',
      [],
    );
  }

  {
    my ($sql, @bind) = $sa->select('bar', '*', {}, { for => \'baz' } );
    is_same_sql_bind(
      $sql,
      \@bind,
      'SELECT * FROM bar FOR baz',
      [],
    );
  }
}


# Make sure the carp/croak override in SQLAC works (via SQLMaker)
my $file = quotemeta (__FILE__);
throws_ok (sub {
  $schema->resultset ('Artist')->search ({}, { order_by => { -asc => 'stuff', -desc => 'staff' } } )->as_query;
}, qr/$file/, 'Exception correctly croak()ed');

done_testing;
