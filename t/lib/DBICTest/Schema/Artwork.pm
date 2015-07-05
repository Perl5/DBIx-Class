package # hide from PAUSE
    DBICTest::Schema::Artwork;

use warnings;
use strict;

use base 'DBICTest::BaseResult';
use DBICTest::Util 'check_customcond_args';

__PACKAGE__->table('cd_artwork');
__PACKAGE__->add_columns(
  'cd_id' => {
    data_type => 'integer',
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key('cd_id');
__PACKAGE__->belongs_to('cd', 'DBICTest::Schema::CD', 'cd_id');
__PACKAGE__->has_many('images', 'DBICTest::Schema::Image', 'artwork_id');

__PACKAGE__->has_many('artwork_to_artist', 'DBICTest::Schema::Artwork_to_Artist', 'artwork_cd_id');
__PACKAGE__->many_to_many('artists', 'artwork_to_artist', 'artist');

# both to test manytomany via double custom rel (deliberate misnamed accessor clash)
__PACKAGE__->many_to_many('artist_limited_rank', 'artwork_to_artist_via_customcond', 'artist_limited_rank');
__PACKAGE__->many_to_many('artist_limited_rank_opaque', 'artwork_to_artist_via_opaque_customcond', 'artist_limited_rank_opaque');

__PACKAGE__->has_many('artwork_to_artist_via_customcond', 'DBICTest::Schema::Artwork_to_Artist',
  sub {
    # This is for test purposes only. A regular user does not
    # need to sanity check the passed-in arguments, this is what
    # the tests are for :)
    my $args = &check_customcond_args;

    return (
      { "$args->{foreign_alias}.artwork_cd_id" => { -ident => "$args->{self_alias}.cd_id" },
      },
      $args->{self_result_object} && {
        "$args->{foreign_alias}.artwork_cd_id" => $args->{self_result_object}->cd_id,
      }
    );
  }
);

__PACKAGE__->has_many('artwork_to_artist_via_opaque_customcond', 'DBICTest::Schema::Artwork_to_Artist',
  sub {
    # This is for test purposes only. A regular user does not
    # need to sanity check the passed-in arguments, this is what
    # the tests are for :)
    my $args = &check_customcond_args;

    return (
      { "$args->{foreign_alias}.artwork_cd_id" => { -ident => "$args->{self_alias}.cd_id" } },
    );
  }
);

__PACKAGE__->many_to_many('all_artists_via_opaque_customcond', 'artwork_to_artist_via_opaque_customcond', 'artist');


1;
