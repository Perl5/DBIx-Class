package # hide from PAUSE
    DBICTest::Schema::Track;

use warnings;
use strict;

use base 'DBICTest::BaseResult';
use DBICTest::Util 'check_customcond_args';

__PACKAGE__->load_components(qw{
    +DBICTest::DeployComponent
    InflateColumn::DateTime
    Ordered
});

__PACKAGE__->table('track');
__PACKAGE__->add_columns(
  'trackid' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'cd' => {
    data_type => 'integer',
  },
  'position' => {
    data_type => 'int',
    accessor => 'pos',
  },
  'title' => {
    data_type => 'varchar',
    size      => 100,
  },
  last_updated_on => {
    data_type => 'datetime',
    accessor => 'updated_date',
    is_nullable => 1
  },
  last_updated_at => {
    data_type => 'datetime',
    is_nullable => 1
  },
);
__PACKAGE__->set_primary_key('trackid');

__PACKAGE__->add_unique_constraint([ qw/cd position/ ]);
__PACKAGE__->add_unique_constraint([ qw/cd title/ ]);

__PACKAGE__->position_column ('position');
__PACKAGE__->grouping_column ('cd');

# the undef condition in this rel is *deliberate*
# tests oddball legacy syntax
__PACKAGE__->belongs_to( cd => 'DBICTest::Schema::CD', undef, {
    proxy => { cd_title => 'title' },
});
# custom condition coderef
__PACKAGE__->belongs_to( cd_cref_cond => 'DBICTest::Schema::CD',
sub {
  # This is for test purposes only. A regular user does not
  # need to sanity check the passed-in arguments, this is what
  # the tests are for :)
  my $args = &check_customcond_args;

  return (
    {
      "$args->{foreign_alias}.cdid" => { -ident => "$args->{self_alias}.cd" },
    },

    ! $args->{self_result_object} ? () : {
     "$args->{foreign_alias}.cdid" => $args->{self_result_object}->get_column('cd')
    },

    ! $args->{foreign_values} ? () : {
     "$args->{self_alias}.cd" => $args->{foreign_values}{cdid}
    },
  );
}
);
__PACKAGE__->belongs_to( disc => 'DBICTest::Schema::CD' => 'cd', {
    proxy => 'year'
});

__PACKAGE__->might_have( cd_single => 'DBICTest::Schema::CD', 'single_track' );
__PACKAGE__->might_have( lyrics => 'DBICTest::Schema::Lyrics', 'track_id' );

__PACKAGE__->belongs_to(
    "year1999cd",
    "DBICTest::Schema::Year1999CDs",
    'cd',
    { join_type => 'left' },  # the relationship is of course optional
);
__PACKAGE__->belongs_to(
    "year2000cd",
    "DBICTest::Schema::Year2000CDs",
    'cd',
    { join_type => 'left' },
);

__PACKAGE__->has_many (
  next_tracks => __PACKAGE__,
  sub {
    # This is for test purposes only. A regular user does not
    # need to sanity check the passed-in arguments, this is what
    # the tests are for :)
    my $args = &check_customcond_args;

    return (
      { "$args->{foreign_alias}.cd"       => { -ident => "$args->{self_alias}.cd" },
        "$args->{foreign_alias}.position" => { '>' => { -ident => "$args->{self_alias}.position" } },
      },
      $args->{self_result_object} && {
        "$args->{foreign_alias}.cd"       => $args->{self_result_object}->get_column('cd'),
        "$args->{foreign_alias}.position" => { '>' => $args->{self_result_object}->pos },
      }
    )
  }
);

__PACKAGE__->has_many (
  deliberately_broken_all_cd_tracks => __PACKAGE__,
  sub {
    # This is for test purposes only. A regular user does not
    # need to sanity check the passed-in arguments, this is what
    # the tests are for :)
    my $args = &check_customcond_args;

    return {
      "$args->{foreign_alias}.cd" => "$args->{self_alias}.cd"
    };
  }
);

our $hook_cb;

sub sqlt_deploy_hook {
  my $class = shift;

  $hook_cb->($class, @_) if $hook_cb;
  $class->next::method(@_) if $class->next::can;
}

1;
