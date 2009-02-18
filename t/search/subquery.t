#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Data::Dumper;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

plan tests => 4;

my $schema = DBICTest->init_schema();
my $art_rs = $schema->resultset('Artist');
my $cdrs = $schema->resultset('CD');

{
  my $cdrs2 = $cdrs->search({
    artist_id => { 'in' => $art_rs->search({}, { rows => 1 })->get_column( 'id' )->as_query },
  });

  my $arr = $cdrs2->as_query;
  my ($query, @bind) = @{$$arr};
  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.cdid,me.artist,me.title,me.year,me.genreid,me.single_track FROM cd me WHERE artist_id IN ( SELECT id FROM artist me LIMIT 1 )",
    [],
  );
}

TODO: {
#  local $TODO = "'+select' doesn't work with as_query yet.";
  my $rs = $art_rs->search(
    {},
    {
      '+select' => [
        $cdrs->search({}, { rows => 1 })->get_column('id')->as_query,
      ],
      '+as' => [
        'cdid',
      ],
    },
  );

  my $arr = $rs->as_query;
  my ($query, @bind) = @{$$arr};
  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.artistid, me.name, me.rank, me.charfield, (SELECT id FROM cds LIMIT 1) AS cdid FROM artist me",
    [],
  );
}

TODO: {
#  local $TODO = "'from' doesn't work with as_query yet.";
  my $rs = $cdrs->search(
    {},
    {
      alias => 'cd2',
      from => [
        { cd2 => $cdrs->search({ id => { '>' => 20 } })->as_query },
      ],
    },
  );

  my $arr = $rs->as_query;
  my ($query, @bind) = @{$$arr};
  is_same_sql_bind(
    $query, \@bind,
    "SELECT cd2.cdid, cd2.artist, cd2.title, cd2.year, cd2.genreid, cd2.single_track FROM (SELECT me.artistid, me.name, me.rank, me.charfield FROM cds me WHERE id > 20) cd2",
    [],
  );
}

TODO: {
#  local $TODO = "The subquery isn't being wrapped in parens for some reason.";
  my $rs = $cdrs->search({
    year => {
      '=' => $cdrs->search(
        { artistid => { '=' => \'me.artistid' } },
        { alias => 'inner' }
      )->get_column('year')->max_rs->as_query,
    },
  });
  my $arr = $rs->as_query;
  my ($query, @bind) = @{$$arr};
  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track FROM cd me WHERE year = (SELECT MAX(inner.year) FROM cd inner WHERE artistid = me.artistid)",
    [],
  );
}

my $rs = $cdrs->search( undef, { alias => 'foo' } );
warn ${$rs->as_query}->[0], $/;
__END__
