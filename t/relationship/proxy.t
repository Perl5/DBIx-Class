use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd = $schema->resultset('CD')->find(2);
is($cd->notes, $cd->liner_notes->notes, 'notes proxy ok');
is($cd->artist_name, $cd->artist->name, 'artist_name proxy ok');

my $track = $cd->tracks->first;
is($track->cd_title, $track->cd->title, 'cd_title proxy ok');
is($track->cd_title, $cd->title, 'cd_title proxy II ok');
is($track->year, $cd->year, 'year proxy ok');

my $tag = $schema->resultset('Tag')->first;
is($tag->year, $tag->cd->year, 'year proxy II ok');
is($tag->cd_title, $tag->cd->title, 'cd_title proxy III ok');

my $bookmark = $schema->resultset('Bookmark')->create ({
  link => { url => 'http://cpan.org', title => 'CPAN' },
});
my $link = $bookmark->link;
ok($bookmark->link_id == $link->id, 'link_id proxy ok');
is($bookmark->link_url, $link->url, 'link_url proxy ok');
is($bookmark->link_title, $link->title, 'link_title proxy ok');

my $cd_source_class = $schema->class('CD');
throws_ok {
    $cd_source_class->add_relationship('artist_regex',
        'DBICTest::Schema::Artist', {
            'foreign.artistid' => 'self.artist'
        }, { proxy => qr/\w+/ }
    ) } qr/unable \s to \s process \s the \s \'proxy\' \s argument/ix,
    'proxy attr with a regex ok';
throws_ok {
    $cd_source_class->add_relationship('artist_sub',
        'DBICTest::Schema::Artist', {
            'foreign.artistid' => 'self.artist'
        }, { proxy => sub {} }
    ) } qr/unable \s to \s process \s the \s \'proxy\' \s argument/ix,
    'proxy attr with a sub ok';

done_testing;
