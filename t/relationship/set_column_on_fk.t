use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();


# test with relname == colname
my $bookmark = $schema->resultset("Bookmark")->find(1);
ok( $bookmark->has_column ('link'), 'Right column name' );
ok( $bookmark->has_relationship ('link'), 'Right rel name' );

my $link = $bookmark->link;

my $new_link = $schema->resultset("Link")->create({
  url     => "http://bugsarereal.com",
  title   => "bugsarereal.com",
  id      => 9,
});

is( $bookmark->link->id, 1, 'Initial relation id' );

$bookmark->set_column( 'link', 9 );
is( $bookmark->link->id, 9, 'Correct object re-selected after belongs_to set' );

$bookmark->discard_changes;
is( $bookmark->link->id, 1, 'Pulled the correct old object after belongs_to reset' );


$bookmark->link($new_link);
is( $bookmark->get_column('link'), 9, 'Correct column set from related' );

$bookmark->discard_changes;
is( $bookmark->link->id, 1, 'Pulled the correct old object after belongs_to reset' );


$bookmark->link(9);
is( $bookmark->link->id, 9, 'Correct object selected on deflated accessor set');

$bookmark->discard_changes;
is( $bookmark->link->id, 1, 'Pulled the correct old object after belongs_to reset' );


$bookmark->update({ link => 9 });
is( $bookmark->link->id, 9, 'Correct relationship after update' );
is( $bookmark->get_from_storage->link->id, 9, 'Correct relationship after re-select' );


# test with relname != colname
my $lyric = $schema->resultset('Lyrics')->create({ track_id => 5 });
is( $lyric->track->id, 5, 'Initial relation id');

$lyric->track_id(6);
my $track6 = $lyric->track;
is( $track6->trackid, 6, 'Correct object re-selected after belongs_to set');

$lyric->discard_changes;
is( $lyric->track->trackid, 5, 'Pulled the correct old rel object after belongs_to reset');

$lyric->track($track6);
is( $lyric->track_id, 6, 'Correct column set from related');

$lyric->discard_changes;
is( $lyric->track->trackid, 5, 'Pulled the correct old rel object after belongs_to reset');

$lyric->update({ track => $track6 });
is( $lyric->track->trackid, 6, 'Correct relationship obj after update' );
is( $lyric->get_from_storage->track->trackid, 6, 'Correct relationship after re-select' );

done_testing;
