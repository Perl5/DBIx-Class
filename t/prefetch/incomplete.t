use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

lives_ok(sub {
  # while cds.* will be selected anyway (prefetch currently forces the result of _resolve_prefetch)
  # only the requested me.name/me.artistid columns will be fetched.

  # reference sql with select => [...]
  #   SELECT me.name, cds.title, me.artistid, cds.cdid, cds.artist, cds.title, cds.year, cds.genreid, cds.single_track FROM ...

  my $rs = $schema->resultset('Artist')->search(
    { 'cds.title' => { '!=', 'Generic Manufactured Singles' } },
    {
      prefetch => [ qw/ cds / ],
      order_by => [ { -desc => 'me.name' }, 'cds.title' ],
      select => [qw/ me.name cds.title me.artistid / ],
    },
  );

  is ($rs->count, 2, 'Correct number of collapsed artists');
  my $we_are_goth = $rs->first;
  is ($we_are_goth->name, 'We Are Goth', 'Correct first artist');
  is ($we_are_goth->cds->count, 1, 'Correct number of CDs for first artist');
  is ($we_are_goth->cds->first->title, 'Come Be Depressed With Us', 'Correct cd for artist');
}, 'explicit prefetch on a keyless object works');

lives_ok ( sub {

  my $rs = $schema->resultset('CD')->search(
    {},
    {
      order_by => [ { -desc => 'me.year' } ],
    }
  );
  my $years = [qw/ 2001 2001 1999 1998 1997/];

  is_deeply (
    [ $rs->search->get_column('me.year')->all ],
    $years,
    'Expected years (at least one duplicate)',
  );

  my @cds_and_tracks;
  for my $cd ($rs->all) {
    my $data = { year => $cd->year, cdid => $cd->cdid };
    for my $tr ($cd->tracks->all) {
      push @{$data->{tracks}}, { $tr->get_columns };
    }
    push @cds_and_tracks, $data;
  }

  my $pref_rs = $rs->search ({}, { columns => [qw/year cdid/], prefetch => 'tracks' });

  my @pref_cds_and_tracks;
  for my $cd ($pref_rs->all) {
    my $data = { $cd->get_columns };
    for my $tr ($cd->tracks->all) {
      push @{$data->{tracks}}, { $tr->get_columns };
    }
    push @pref_cds_and_tracks, $data;
  }

  is_deeply (
    \@pref_cds_and_tracks,
    \@cds_and_tracks,
    'Correct collapsing on non-unique primary object'
  );

  is_deeply (
    [ $pref_rs->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' })->all ],
    \@cds_and_tracks,
    'Correct HRI collapsing on non-unique primary object'
  );

}, 'weird collapse lives');


lives_ok(sub {
  # test implicit prefetch as well

  my $rs = $schema->resultset('CD')->search(
    { title => 'Generic Manufactured Singles' },
    {
      join=> 'artist',
      select => [qw/ me.title artist.name / ],
    }
  );

  my $cd = $rs->next;
  is ($cd->title, 'Generic Manufactured Singles', 'CD title prefetched correctly');
  isa_ok ($cd->artist, 'DBICTest::Artist');
  is ($cd->artist->name, 'Random Boy Band', 'Artist object has correct name');

}, 'implicit keyless prefetch works');

# sane error
throws_ok(
  sub {
    $schema->resultset('Track')->search({}, { join => { cd => 'artist' }, '+columns' => 'artist.name' } )->next;
  },
  qr|\QCan't inflate prefetch into non-existent relationship 'artist' from 'Track', check the inflation specification (columns/as) ending in '...artist.name'|,
  'Sensible error message on mis-specified "as"',
);

done_testing;
