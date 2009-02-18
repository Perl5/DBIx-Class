#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Data::Dumper;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

plan tests => 1;

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

__END__
