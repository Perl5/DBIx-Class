use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

# Test various new() invocations - this is all about backcompat, making
# sure that insert() still works as expected by legacy code.
#
# What we essentially do is multi-instantiate objects, making sure nothing
# gets inserted. Then we add some more objects to the mix either via
# new_related() or by setting an accessor directly (or both) - again
# expecting no inserts. Then after calling insert() on the starter object
# we expect everything supplied to new() to get inserted, as well as any
# relations whose PK's are necessary to complete the objects supplied
# to new(). All other objects should be insert()able afterwards too.


{
    my $new_artist = $schema->resultset("Artist")->new_result({ 'name' => 'Depeche Mode' });
    my $new_related_cd = $new_artist->new_related('cds', { 'title' => 'Leave in Silence', 'year' => 1982});
    lives_ok {
        $new_artist->insert;
        $new_related_cd->insert;
    } 'Staged insertion successful';
    ok($new_artist->in_storage, 'artist inserted');
    ok($new_related_cd->in_storage, 'new_related_cd inserted');
}

{
    my $new_artist = $schema->resultset("Artist")->new_result({ 'name' => 'Mode Depeche' });
    my $new_related_cd = $new_artist->new_related('cds', { 'title' => 'Leave Slightly Noisily', 'year' => 1982});
    lives_ok {
        $new_related_cd->insert;
    } 'CD insertion survives by finding artist';
    ok($new_artist->in_storage, 'artist inserted');
    ok($new_related_cd->in_storage, 'new_related_cd inserted');
}

{
    my $new_cd = $schema->resultset('CD')->new ({ 'title' => 'Leave Loudly While Singing Off Key', 'year' => 1982});
    my $new_artist = $schema->resultset("Artist")->new ({ 'name' => 'Depeche Mode 2: Insertion Boogaloo' });
    $new_cd->artist ($new_artist);

    lives_ok {
        $new_cd->insert;
    } 'CD insertion survives by inserting artist';
    ok($new_cd->in_storage, 'new_related_cd inserted');
    ok($new_artist->in_storage, 'artist inserted');

    my $retrieved_cd = $schema->resultset('CD')->find ({ 'title' => 'Leave Loudly While Singing Off Key'});
    ok ($retrieved_cd, 'CD found in db');
    is ($retrieved_cd->artist->name, 'Depeche Mode 2: Insertion Boogaloo', 'Correct artist attached to cd');
}

{
    my $new_cd = $schema->resultset('CD')->new ({ 'title' => 'Leave screaming Off Key in the nude', 'year' => 1982});
    my $new_related_artist = $new_cd->new_related( artist => { 'name' => 'Depeche Mode 3: Insertion Boogaloo' });
    lives_ok {
        $new_related_artist->insert;
        $new_cd->insert;
    } 'CD insertion survives after inserting artist';
    ok($new_cd->in_storage, 'cd inserted');
    ok($new_related_artist->in_storage, 'artist inserted');

    my $retrieved_cd = $schema->resultset('CD')->find ({ 'title' => 'Leave screaming Off Key in the nude'});
    ok ($retrieved_cd, 'CD found in db');
    is ($retrieved_cd->artist->name, 'Depeche Mode 3: Insertion Boogaloo', 'Correct artist attached to cd');
}

# test both sides of a 1:(1|0)
{
  for my $reldir ('might_have', 'belongs_to') {
    my $artist = $schema->resultset('Artist')->next;

    my $new_track = $schema->resultset('Track')->new ({
      title => "$reldir: First track of latest cd",
      cd => {
        title => "$reldir: Latest cd",
        year => 2666,
        artist => $artist,
      },
    });

    my $new_single = $schema->resultset('CD')->new ({
      artist => $artist,
      title => "$reldir: Awesome first single",
      year => 2666,
    });

    if ($reldir eq 'might_have') {
      $new_track->cd_single ($new_single);
      $new_track->insert;
    }
    else {
      $new_single->single_track ($new_track);
      $new_single->insert;
    }

    ok ($new_single->in_storage, "$reldir single inserted");
    ok ($new_track->in_storage, "$reldir track inserted");

    my $new_cds = $artist->search_related ('cds',
      { year => '2666' },
      { prefetch => 'tracks', order_by => 'cdid' }
    );

    is_deeply (
      [$new_cds->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator'})->all ],
      [
        {
          artist => 1,
          cdid => 10,
          genreid => undef,
          single_track => undef,
          title => "$reldir: Latest cd",
          tracks => [
            {
              cd => 10,
              last_updated_at => undef,
              last_updated_on => undef,
              position => 1,
              title => "$reldir: First track of latest cd",
              trackid => 19
            }
          ],
          year => 2666
        },
        {
          artist => 1,
          cdid => 11,
          genreid => undef,
          single_track => 19,
          title => "$reldir: Awesome first single",
          tracks => [],
          year => 2666
        },
      ],
      'Expected rows created in database',
    );

    $new_cds->delete_all;
  }
}

{
    my $new_cd = $schema->resultset("CD")->new_result({});
    my $new_related_artist = $new_cd->new_related('artist', { 'name' => 'Marillion',});
    lives_ok (
        sub {
            $new_related_artist->insert;
            $new_cd->title( 'Misplaced Childhood' );
            $new_cd->year ( 1985 );
            $new_cd->artist( $new_related_artist );  # For exact backward compatibility
            $new_cd->insert;
        },
        'Reversed staged insertion successful'
    );
    ok($new_related_artist->in_storage, 'related artist inserted');
    ok($new_cd->in_storage, 'cd inserted');
}

done_testing;
