use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib qw(t/lib);
use Data::Dumper;
use DBICTest;    # do not remove even though it is not used

#15:01 <@ribasushi> dhoss: you are complicating your life
#15:01 <@ribasushi> dhoss: start from the other side:
#15:02 <@ribasushi> if currently you add a test to t/??ordered.t that does
#                   $ordered_rs->search({ condition to not delete
#                   everything})->delete;
#15:03 <@ribasushi> dhoss: and then examine the database - you will see
#                   numbering is broken
#15:03 <@ribasushi> dhoss: use your newly found component injection powers to
#                   change the delete into a delete_all behind the scenes - the
#                   remaining rows will then be reordered correctly
#15:03 <@ribasushi> dhoss: this way you both test that injection works AND you
#                   fix Ordered

my $schema = DBICTest->init_schema();
my $artist =
  $schema->resultset('Artist')->search( {}, { rows => 1 } )
  ->single;    # braindead sqlite
my $cd = $schema->resultset('CD')->create(
  {
    artist => $artist,
    title  => 'Get in order',
    year   => 2009,
    tracks => [ { title => 'T1' }, { title => 'T2' }, { title => 'T3' }, ],
  }
);


lives_ok( sub { $cd->delete },
  "Cascade delete on ordered has_many doesn't bomb" );
is_deeply(
  mro::get_linear_isa( ref $schema->resultset("Track") ),
  [
    qw(
    DBICTest::BaseResultSet::+::_DBIx_Class_Ordered_ResultSet 
    DBIx::Class::Ordered::ResultSet
    DBICTest::BaseResultSet
    DBIx::Class::ResultSet
    DBIx::Class
    DBIx::Class::Componentised
    Class::C3::Componentised
    Class::Accessor::Grouped
    )
  ],
  "MRO for class is correct"
);
done_testing();
