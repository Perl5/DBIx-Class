use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

# From http://lists.scsys.co.uk/pipermail/dbix-class/2013-February/011119.html
#
# > Right, at this point we have an "undefined situation turned into an
# > unplanned feature", therefore 0.08242 will downgrade the exception to a
# > single-warning-per-process. This seems like a sane middle ground for
# > "you gave me an 'as' that worked by accident before - fix it at your
# > convenience".
#
# When the things were reshuffled it became apparent implementing a warning
# for the HRI case *only* is going to complicate the code a lot, without
# adding much benefit at this point. So just make sure everything works the
# way it used to and move on


my $s = DBICTest->init_schema;

my $rs_2nd_track = $s->resultset('Track')->search(
  { 'me.position' => 2 },
  {
    join => { cd => 'artist' },
    columns => [ 'me.title', { 'artist.cdtitle' => 'cd.title' }, 'artist.name' ],
    order_by => [ 'artist.name', { -desc => 'cd.cdid' }, 'me.trackid' ],
  }
);

is_deeply (
  [ map { $_->[-1] } $rs_2nd_track->cursor->all ],
  [ ('Caterwauler McCrae') x 3, 'Random Boy Band', 'We Are Goth' ],
  'Artist name cartesian product correct off cursor',
);

is_deeply (
  $rs_2nd_track->all_hri,
  [
    {
      artist => { cdtitle => "Caterwaulin' Blues", name => "Caterwauler McCrae" },
      title => "Howlin"
    },
    {
      artist => { cdtitle => "Forkful of bees", name => "Caterwauler McCrae" },
      title => "Stripy"
    },
    {
      artist => { cdtitle => "Spoonful of bees", name => "Caterwauler McCrae" },
      title => "Apiary"
    },
    {
      artist => { cdtitle => "Generic Manufactured Singles", name => "Random Boy Band" },
      title => "Boring Song"
    },
    {
      artist => { cdtitle => "Come Be Depressed With Us", name => "We Are Goth" },
      title => "Under The Weather"
    }
  ],
  'HRI with invalid inflate map works'
);

throws_ok
  { $rs_2nd_track->next }
  qr!\QInflation into non-existent relationship 'artist' of 'Track' requested, check the inflation specification (columns/as) ending in '...artist.name'!,
  'Correct exception on illegal ::Row inflation attempt'
;

# make sure has_many column redirection does not do weird stuff when collapse is requested
for my $pref_args (
  { prefetch => 'cds'},
  { collapse => 1 }
) {
  for my $col_and_join_args (
    { '+columns' => { 'cd_title' => 'cds_2.title' }, join => [ 'cds', 'cds' ] },
    { '+columns' => { 'cd_title' => 'cds.title' }, join => 'cds' },
    { '+columns' => { 'cd_gr_name' => 'genre.name' }, join => { cds => 'genre' } },
  ) {
    for my $call (qw(next all first)) {

      my $weird_rs = $s->resultset('Artist')->search({}, {
        %$col_and_join_args, %$pref_args,
      });

      throws_ok
        { $weird_rs->$call }
        qr/\QResult collapse not possible - selection from a has_many source redirected to the main object/
      for (1,2);
    }
  }
}

done_testing;
