#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

plan tests => 4;

my $schema = DBICTest->init_schema();
my $art_rs = $schema->resultset('Artist');
my $cdrs = $schema->resultset('CD');

{
  my $arr = $art_rs->as_query;
  my ($query, @bind) = @{$$arr};

  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me", [],
  );
}

$art_rs = $art_rs->search({ name => 'Billy Joel' });

{
  my $arr = $art_rs->as_query;
  my ($query, @bind) = @{$$arr};

  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me WHERE ( name = ? )",
    [ [ name => 'Billy Joel' ] ],
  );
}

$art_rs = $art_rs->search({ rank => 2 });

{
  my $arr = $art_rs->as_query;
  my ($query, @bind) = @{$$arr};

  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me WHERE ( ( ( rank = ? ) AND ( name = ? ) ) )",
    [ [ rank => 2 ], [ name => 'Billy Joel' ] ],
  );
}

my $rscol = $art_rs->get_column( 'charfield' );

{
  my $arr = $rscol->as_query;
  my ($query, @bind) = @{$$arr};

  is_same_sql_bind(
    $query, \@bind,
    "SELECT me.charfield FROM artist me WHERE ( ( ( rank = ? ) AND ( name = ? ) ) )",
    [ [ rank => 2 ], [ name => 'Billy Joel' ] ],
  );
}

my $cdrs2 = $cdrs->search({
  artist_id => {
    -in => $art_rs->get_column( 'id' )->as_query,
  },
});

my @x = $cdrs2->all;
use Data::Dumper; warn Dumper \@x;
__END__
{
  my $arr = $cdrs2->as_query;
  my ($query, @bind) = @{$$arr};
}

__END__
