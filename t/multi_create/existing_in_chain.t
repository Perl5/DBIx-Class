use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan 'no_plan';

my $schema = DBICTest->init_schema();

{
  my $counts;
  $counts->{$_} = $schema->resultset($_)->count for qw/Track CD Genre/;

  lives_ok (sub {
    my $existing_nogen_cd = $schema->resultset('CD')->search (
      { 'genre.genreid' => undef },
      { join => 'genre' },
    )->first;

    $schema->resultset('Track')->create ({
      title => 'Sugar-coated',
      cd => {
        title => $existing_nogen_cd->title,
        genre => {
          name => 'sugar genre',
        }
      }
    });

    is ($schema->resultset('Track')->count, $counts->{Track} + 1, '1 new track');
    is ($schema->resultset('CD')->count, $counts->{CD}, 'No new cds');
    is ($schema->resultset('Genre')->count, $counts->{Genre} + 1, '1 new genre');

    is ($existing_nogen_cd->genre->title,  'sugar genre', 'Correct genre assigned to CD');
  });
}

{
  my $counts;
  $counts->{$_} = $schema->resultset($_)->count for qw/Artist CD Producer/;

  lives_ok (sub {
    my $artist = $schema->resultset('Artist')->first;
    my $producer = $schema->resultset('Producer')->create ({ name => 'the queen of england' });

    $schema->resultset('CD')->create ({
      artist => $artist,
      title => 'queen1',
      year => 2007,
      cd_to_producer => [
        {
          producer => {
          name => $producer->name,
            producer_to_cd => [
              {
                cd => {
                  title => 'queen2',
                  year => 2008,
                  artist => $artist,
                },
              },
            ],
          },
        },
      ],
    });

    is ($schema->resultset('Artist')->count, $counts->{Artist}, 'No new artists');
    is ($schema->resultset('Producer')->count, $counts->{Producer} + 1, '1 new producers');
    is ($schema->resultset('CD')->count, $counts->{CD} + 2, '2 new cds');

    is ($producer->cds->count, 2, 'CDs assigned to correct producer');
    is_deeply (
      [ $producer->cds->search ({}, { order_by => 'title' })->get_column('title')->all],
      [ qw/queen1 queen2/ ],
      'Correct cd names',
    );
  });
}

1;
