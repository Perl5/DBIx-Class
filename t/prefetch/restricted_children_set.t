use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cds_rs = $schema->resultset('CD')->search(
  [
    {
      'me.title' => "Caterwaulin' Blues",
      'cds.title' => { '!=' => 'Forkful of bees' }
    },
    {
      'me.title' => { '!=', => "Caterwaulin' Blues" },
      'cds.title' => 'Forkful of bees'
    },
  ],
  {
    order_by => [qw(me.cdid cds.title)],
    prefetch => { artist => 'cds' },
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
  },
);

is_deeply [ $cds_rs->all ], [
  {
    'single_track' => undef,
    'cdid' => '1',
    'artist' => {
      'cds' => [
        {
          'single_track' => undef,
          'artist' => '1',
          'cdid' => '2',
          'title' => 'Forkful of bees',
          'genreid' => undef,
          'year' => '2001'
        },
      ],
      'artistid' => '1',
      'charfield' => undef,
      'name' => 'Caterwauler McCrae',
      'rank' => '13'
    },
    'title' => 'Spoonful of bees',
    'year' => '1999',
    'genreid' => '1'
  },
  {
    'single_track' => undef,
    'cdid' => '2',
    'artist' => {
      'cds' => [
        {
          'single_track' => undef,
          'artist' => '1',
          'cdid' => '2',
          'title' => 'Forkful of bees',
          'genreid' => undef,
          'year' => '2001'
        },
      ],
      'artistid' => '1',
      'charfield' => undef,
      'name' => 'Caterwauler McCrae',
      'rank' => '13'
    },
    'title' => 'Forkful of bees',
    'year' => '2001',
    'genreid' => undef
  },
  {
    'single_track' => undef,
    'cdid' => '3',
    'artist' => {
      'cds' => [
        {
          'single_track' => undef,
          'artist' => '1',
          'cdid' => '3',
          'title' => 'Caterwaulin\' Blues',
          'genreid' => undef,
          'year' => '1997'
        },
        {
          'single_track' => undef,
          'artist' => '1',
          'cdid' => '1',
          'title' => 'Spoonful of bees',
          'genreid' => '1',
          'year' => '1999'
        }
      ],
      'artistid' => '1',
      'charfield' => undef,
      'name' => 'Caterwauler McCrae',
      'rank' => '13'
    },
    'title' => 'Caterwaulin\' Blues',
    'year' => '1997',
    'genreid' => undef
  }
], 'multi-level prefetch with restrictions ok';

done_testing;
