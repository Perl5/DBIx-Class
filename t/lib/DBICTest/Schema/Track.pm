package # hide from PAUSE
    DBICTest::Schema::Track;

use base qw/DBICTest::BaseResult/;
use Carp qw/confess/;

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


__PACKAGE__->belongs_to( cd => 'DBICTest::Schema::CD', undef, {
    proxy => { cd_title => 'title' },
});
__PACKAGE__->belongs_to( disc => 'DBICTest::Schema::CD' => 'cd', {
    proxy => 'year'
});

__PACKAGE__->might_have( cd_single => 'DBICTest::Schema::CD', 'single_track' );
__PACKAGE__->might_have( lyrics => 'DBICTest::Schema::Lyrics', 'track_id' );

__PACKAGE__->belongs_to(
    "year1999cd",
    "DBICTest::Schema::Year1999CDs",
    { "foreign.cdid" => "self.cd" },
    { join_type => 'left' },  # the relationship is of course optional
);
__PACKAGE__->belongs_to(
    "year2000cd",
    "DBICTest::Schema::Year2000CDs",
    { "foreign.cdid" => "self.cd" },
    { join_type => 'left' },
);

__PACKAGE__->has_many (
  next_tracks => __PACKAGE__,
  sub {
    my $args = shift;

    # This is for test purposes only. A regular user does not
    # need to sanity check the passed-in arguments, this is what
    # the tests are for :)
    my @missing_args = grep { ! defined $args->{$_} }
      qw/self_alias foreign_alias self_resultsource foreign_relname/;
    confess "Required arguments not supplied to custom rel coderef: @missing_args\n"
      if @missing_args;

    return (
      { "$args->{foreign_alias}.cd"       => { -ident => "$args->{self_alias}.cd" },
        "$args->{foreign_alias}.position" => { '>' => { -ident => "$args->{self_alias}.position" } },
      },
      $args->{self_rowobj} && {
        "$args->{foreign_alias}.cd"       => $args->{self_rowobj}->get_column('cd'),
        "$args->{foreign_alias}.position" => { '>' => $args->{self_rowobj}->pos },
      }
    )
  }
);

our $hook_cb;

sub sqlt_deploy_hook {
  my $class = shift;

  $hook_cb->($class, @_) if $hook_cb;
  $class->next::method(@_) if $class->next::can;
}

1;
