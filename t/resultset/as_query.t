use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();
my $art_rs = $schema->resultset('Artist');
my $cdrs = $schema->resultset('CD');

{
  is_same_sql_bind(
    $art_rs->as_query,
    "(SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me)", [],
  );
}

$art_rs = $art_rs->search({ name => 'Billy Joel' });

my $name_resolved_bind = [
  { sqlt_datatype => 'varchar', sqlt_size  => 100, dbic_colname => 'name' }
    => 'Billy Joel'
];

{
  is_same_sql_bind(
    $art_rs->as_query,
    "(SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me WHERE ( name = ? ))",
    [ $name_resolved_bind ],
  );
}

$art_rs = $art_rs->search({ rank => 2 });

my $rank_resolved_bind = [
  { sqlt_datatype => 'integer', dbic_colname => 'rank' }
    => 2
];

{
  is_same_sql_bind(
    $art_rs->as_query,
    "(SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me WHERE ( ( ( rank = ? ) AND ( name = ? ) ) ) )",
    [ $rank_resolved_bind, $name_resolved_bind ],
  );
}

my $rscol = $art_rs->get_column( 'charfield' );

{
  is_same_sql_bind(
    $rscol->as_query,
    "(SELECT me.charfield FROM artist me WHERE ( ( ( rank = ? ) AND ( name = ? ) ) ) )",
    [ $rank_resolved_bind, $name_resolved_bind ],
  );
}

{
  my $rs = $schema->resultset("CD")->search(
    { 'artist.name' => 'Caterwauler McCrae' },
    { join => [qw/artist/]}
  );
  my $subsel_rs = $schema->resultset("CD")->search( { cdid => { IN => $rs->get_column('cdid')->as_query } } );
  is($subsel_rs->count, $rs->count, 'Subselect on PK got the same row count');
}


is_same_sql_bind($schema->resultset('Artist')->search({
   rank => 1,
}, {
   from => $schema->resultset('Artist')->search({ 'name' => 'frew'})->as_query,
})->as_query,
   '(SELECT me.artistid, me.name, me.rank, me.charfield FROM (
     SELECT me.artistid, me.name, me.rank, me.charfield FROM
       artist me
       WHERE (
         ( name = ? )
       )
     ) WHERE (
       ( rank = ? )
     )
   )',
   [
      [{ dbic_colname => 'name', sqlt_datatype => 'varchar', sqlt_size => 100 }, 'frew'],
      [{ dbic_colname => 'rank' }, 1],
   ],
   'from => ...->as_query works'
);

done_testing;
