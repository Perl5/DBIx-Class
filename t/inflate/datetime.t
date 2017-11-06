BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;
use DateTime;

use Test::More;

use DBIx::Class::_Util 'modver_gt_or_eq_and_lt';
use base();
BEGIN {
  plan skip_all => 'base.pm 2.20 (only present in perl 5.19.7) is known to break this test'
    if modver_gt_or_eq_and_lt( 'base', '2.19_01', '2.21' );
}

use Test::Exception;

use DBICTest;
my $schema = DBICTest->init_schema();

my $created;

my %required_create_args = (
  starts_at => "2012-01-01",
  created_on => "2012-01-01",
);

subtest "create with DateTime" => sub {
  $created = $schema->resultset('Event')->create({
      %required_create_args,
      varchar_datetime => DateTime->new(year => 2016, month => 01, day => 01)
    });
  $created->varchar_datetime; # make sure inflated
  is ref($created->varchar_datetime), "DateTime", "varchar_datetime accessor is a datetime";
  is $created->varchar_datetime->date, "2016-01-01", "varchar_datetime has correct datetime";
};

subtest "create with scalar" => sub {
  $created = $schema->resultset('Event')->create({
      %required_create_args,
      varchar_datetime => "2016-01-01",
    });
  $created->varchar_datetime; # make sure inflated
  is ref($created->varchar_datetime), "DateTime", "varchar_datetime accessor is a datetime";
  is $created->varchar_datetime->date, "2016-01-01", "varchar_datetime has correct datetime";
};

subtest "update with column datetime" => sub {
  $created = $schema->resultset('Event')->create({
      %required_create_args,
      varchar_datetime => DateTime->new(year => 2016, month => 01, day => 01)
    });
  $created->varchar_datetime; # make sure inflated
  $created->varchar_datetime(DateTime->new(year => 2017, month => 01, day => 01));
  $created->update;
  is ref($created->varchar_datetime), "DateTime", "varchar_datetime accessor is a datetime";
  is $created->varchar_datetime->date, "2017-01-01", "varchar_datetime has correct datetime";
};

subtest "update with column scalar" => sub {
  $created = $schema->resultset('Event')->create({
      %required_create_args,
      varchar_datetime => DateTime->new(year => 2016, month => 01, day => 01)
    });
  $created->varchar_datetime; # make sure inflated
  $created->varchar_datetime("2017-01-01");
  $created->update;
  is ref($created->varchar_datetime), "DateTime", "varchar_datetime accessor is a datetime";
  is $created->varchar_datetime->date, "2017-01-01", "varchar_datetime has correct datetime";
};

subtest "update with datetime" => sub {
  $created = $schema->resultset('Event')->create({
      %required_create_args,
      varchar_datetime => DateTime->new(year => 2016, month => 01, day => 01)
    });
  $created->varchar_datetime; # make sure inflated
  $created->update({varchar_datetime => DateTime->new(year => 2017, month => 01, day => 01)});
  is ref($created->varchar_datetime), "DateTime", "varchar_datetime accessor is a datetime";
  is $created->varchar_datetime->date, "2017-01-01", "varchar_datetime has correct datetime";
};

subtest "update with scalar" => sub {
  $created = $schema->resultset('Event')->create({
      %required_create_args,
      varchar_datetime => DateTime->new(year => 2016, month => 01, day => 01)
    });
  $created->varchar_datetime; # make sure inflated
  $created->update({varchar_datetime => "2017-01-01"});
  is ref($created->varchar_datetime), "DateTime", "varchar_datetime accessor is a datetime";
  is $created->varchar_datetime->date, "2017-01-01", "varchar_datetime has correct datetime";
};

done_testing;
