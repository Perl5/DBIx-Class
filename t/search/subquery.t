use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;

my $ROWS = DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype;

my $schema = DBICTest->init_schema();
my $art_rs = $schema->resultset('Artist');
my $cdrs = $schema->resultset('CD');

my @tests = (
  {
    rs => $cdrs,
    search => \[ "title = ? AND year LIKE ?", [ title => 'buahaha' ], [ year => '20%' ] ],
    attrs => { rows => 5 },
    sqlbind => \[
      "( SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE (title = ? AND year LIKE ?) LIMIT ?)",
      [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'title' } => 'buahaha' ],
      [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'year' } => '20%' ],
      [ $ROWS => 5 ],
    ],
  },

  {
    rs => $cdrs,
    search => {
      artistid => { 'in' => $art_rs->search({}, { rows => 1 })->get_column( 'artistid' )->as_query },
    },
    sqlbind => \[
      "( SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE artistid IN ( SELECT me.artistid FROM artist me LIMIT ? ) )",
      [ $ROWS => 1 ],
    ],
  },

  {
    rs => $art_rs,
    attrs => {
      'select' => [
        $cdrs->search({}, { rows => 1 })->get_column('id')->as_query,
      ],
    },
    sqlbind => \[
      "( SELECT (SELECT me.id FROM cd me LIMIT ?) FROM artist me )",
      [ $ROWS => 1 ],
    ],
  },

  {
    rs => $art_rs,
    attrs => {
      '+select' => [
        $cdrs->search({}, { rows => 1 })->get_column('id')->as_query,
      ],
    },
    sqlbind => \[
      "( SELECT me.artistid, me.name, me.rank, me.charfield, (SELECT me.id FROM cd me LIMIT ?) FROM artist me )",
      [ $ROWS => 1 ],
    ],
  },

  {
    rs => $cdrs,
    attrs => {
      alias => 'cd2',
      from => [
        { cd2 => $cdrs->search({ artist => { '>' => 20 } })->as_query },
      ],
    },
    sqlbind => \[
      "( SELECT cd2.cdid, cd2.artist, cd2.title, cd2.year, cd2.genreid, cd2.single_track FROM (
            SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE artist > ?
          ) cd2
        )",
      [ { sqlt_datatype => 'integer', dbic_colname => 'artist' } => 20 ]
    ],
  },

  {
    rs => $art_rs,
    attrs => {
      from => [
        { 'me' => 'artist' },
        [
          { 'cds' => $cdrs->search({}, { 'select' => [\'me.artist as cds_artist' ]})->as_query },
          { 'me.artistid' => 'cds_artist' }
        ]
      ]
    },
    sqlbind => \[
      "( SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me JOIN (SELECT me.artist as cds_artist FROM cd me) cds ON me.artistid = cds_artist )"
    ],
  },

  {
    rs => $cdrs,
    attrs => {
      alias => 'cd2',
      from => [
        { cd2 => $cdrs->search(
            { artist => { '>' => 20 } },
            {
                alias => 'cd3',
                from => [
                { cd3 => $cdrs->search( { artist => { '<' => 40 } } )->as_query }
                ],
            }, )->as_query },
      ],
    },
    sqlbind => \[
      "( SELECT cd2.cdid, cd2.artist, cd2.title, cd2.year, cd2.genreid, cd2.single_track
        FROM
          (SELECT cd3.cdid, cd3.artist, cd3.title, cd3.year, cd3.genreid, cd3.single_track
            FROM
              (SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
                FROM cd me WHERE artist < ?) cd3
            WHERE artist > ?) cd2
      )",
      [ { sqlt_datatype => 'integer', dbic_colname => 'artist' } => 40 ],
      [ { dbic_colname => 'artist' } => 20 ], # no rsrc in outer manual from - hence no resolution
    ],
  },

  {
    rs => $cdrs,
    search => {
      year => {
        '=' => $cdrs->search(
          { artistid => { '=' => \'me.artistid' } },
          { alias => 'inner' }
        )->get_column('year')->max_rs->as_query,
      },
    },
    sqlbind => \[
      "( SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE year = (SELECT MAX(inner.year) FROM cd inner WHERE artistid = me.artistid) )",
    ],
  },

  {
    rs => $cdrs,
    attrs => {
      alias => 'cd2',
      from => [
        { cd2 => $cdrs->search({ title => 'Thriller' })->as_query },
      ],
    },
    sqlbind => \[
      "(SELECT cd2.cdid, cd2.artist, cd2.title, cd2.year, cd2.genreid, cd2.single_track FROM (
          SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE title = ?
        ) cd2
      )",
      [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'title' }
          => 'Thriller'
      ]
    ],
  },
);


for my $i (0 .. $#tests) {
  my $t = $tests[$i];
  for my $p (1, 2) {  # repeat everything twice, make sure we do not clobber search arguments
    is_same_sql_bind (
      $t->{rs}->search ($t->{search}, $t->{attrs})->as_query,
      $t->{sqlbind},
      sprintf 'Testcase %d, pass %d', $i+1, $p,
    );
  }
}

done_testing;
