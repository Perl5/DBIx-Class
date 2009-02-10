#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 6;

my $schema	= DBICTest->init_schema();
my $art_rs	= $schema->resultset('Artist');

{
  my $arr = $art_rs->as_query;
  my ($query, @bind) = @$arr;

  is( $query, "SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me" );
  is_deeply( \@bind, [] );
}

$art_rs = $art_rs->search({ name => 'Billy Joel' });

{
  my $arr = $art_rs->as_query;
  my ($query, @bind) = @$arr;

  is( $query, "SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me WHERE ( name = ? )" );
  is_deeply( \@bind, [ [ name => 'Billy Joel' ] ] );
}

$art_rs = $art_rs->search({ rank => 2 });

{
  my $arr = $art_rs->as_query;
  my ($query, @bind) = @$arr;

  is( $query, "SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me WHERE ( ( ( rank = ? ) AND ( name = ? ) ) )" );
  is_deeply( \@bind, [ [ rank => 2 ], [ name => 'Billy Joel' ] ] );
}

__END__
