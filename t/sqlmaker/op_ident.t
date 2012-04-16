use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;

use_ok('DBICTest');

my $schema = DBICTest->init_schema();

my $sql_maker = $schema->storage->sql_maker;

for my $q ('', '"') {

  $sql_maker->quote_char($q);

  is_same_sql_bind (
    \[ $sql_maker->select ('artist', '*', { 'artist.name' => { -ident => 'artist.pseudonym' } } ) ],
    "SELECT *
      FROM ${q}artist${q}
      WHERE ${q}artist${q}.${q}name${q} = ${q}artist${q}.${q}pseudonym${q}
    ",
    [],
  );

  is_same_sql_bind (
    \[ $sql_maker->update ('artist',
      { 'artist.name' => { -ident => 'artist.pseudonym' } },
      { 'artist.name' => { '!=' => { -ident => 'artist.pseudonym' } } },
    ) ],
    "UPDATE ${q}artist${q}
      SET ${q}artist${q}.${q}name${q} = ${q}artist${q}.${q}pseudonym${q}
      WHERE ${q}artist${q}.${q}name${q} != ${q}artist${q}.${q}pseudonym${q}
    ",
    [],
  );
}

done_testing;
