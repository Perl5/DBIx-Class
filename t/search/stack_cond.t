use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest ':DiffSQL';
use SQL::Abstract::Util qw(is_plain_value is_literal_value);
use List::Util 'shuffle';
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Indent = 0;

my $schema = DBICTest->init_schema();

for my $c (
  { cond => undef, sql => 'IS NULL' },
  { cond => { -value => undef }, sql => 'IS NULL' },
  { cond => \'foo', sql => '= foo' },
  { cond => 'foo', sql => '= ?', bind => [
    [ { dbic_colname => "title", sqlt_datatype => "varchar", sqlt_size => 100 } => 'foo' ],
    [ { dbic_colname => "year", sqlt_datatype => "varchar", sqlt_size => 100 } => 'foo' ],
  ]},
  { cond => { -value => 'foo' }, sql => '= ?', bind => [
    [ { dbic_colname => "title", sqlt_datatype => "varchar", sqlt_size => 100 } => 'foo' ],
    [ { dbic_colname => "year", sqlt_datatype => "varchar", sqlt_size => 100 } => 'foo' ],
  ]},
  { cond => \[ '?', "foo" ], sql => '= ?', bind => [
    [ {} => 'foo' ],
    [ {} => 'foo' ],
  ]},
  { cond => { '@>' => { -value => [ 1,2,3 ] } }, sql => '@> ?', bind => [
    [ { dbic_colname => "title", sqlt_datatype => "varchar", sqlt_size => 100 } => [1, 2, 3] ],
    [ { dbic_colname => "year", sqlt_datatype => "varchar", sqlt_size => 100 } => [1, 2, 3] ],
  ]},
) {
  my $rs = $schema->resultset('CD')->search({}, { columns => 'title' });

  my $bare_cond = is_literal_value($c->{cond}) ? { '=', $c->{cond} } : $c->{cond};

  my @query_steps = (
    # these are monkey-wrenches, always there
    { title => { '!=', [ -and => \'bar' ] }, year => { '!=', [ -and => 'bar' ] } },
    { -or => [ genreid => undef, genreid => { '!=' => \42 } ] },
    { -or => [ genreid => undef, genreid => { '!=' => \42 } ] },

    { title => $bare_cond, year => { '=', $c->{cond} } },
    { -and => [ year => $bare_cond, { title => { '=', $c->{cond} } } ] },
    [ year => $bare_cond ],
    [ title => $bare_cond ],
    { -and => [ { year => { '=', $c->{cond} } }, { title => { '=', $c->{cond} } } ] },
    { -and => { -or => { year => { '=', $c->{cond} } } }, -or => { title => $bare_cond } },
  );

  if (my $v = is_plain_value($c->{cond})) {
    push @query_steps,
      { year => $$v },
      { title => $$v },
      { -and => [ year => $$v, title => $$v ] },
    ;
  }

  @query_steps = shuffle @query_steps;

  $rs = $rs->search($_) for @query_steps;

  my @bind = @{$c->{bind} || []};
  {
    no warnings 'misc';
    splice @bind, 1, 0, [ { dbic_colname => "year", sqlt_datatype => "varchar", sqlt_size => 100 } => 'bar' ];
  }

  is_same_sql_bind (
    $rs->as_query,
    "(
      SELECT me.title
        FROM cd me
      WHERE
        ( genreid != 42 OR genreid IS NULL )
          AND
        ( genreid != 42 OR genreid IS NULL )
          AND
        title != bar
          AND
        title $c->{sql}
          AND
        year != ?
          AND
        year $c->{sql}
    )",
    \@bind,
    'Double condition correctly collapsed for steps' . Dumper \@query_steps,
  );
}

done_testing;
