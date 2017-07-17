BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;
use Test::More;

use DBICTest; # do not remove even though it is not used

our $src_count = 100;

for (1 .. $src_count) {
  eval <<EOM or die $@;

  package DBICTest::NS::Stress::Schema::Result::T$_;
  use base qw/DBIx::Class::Core/;
  __PACKAGE__->table($_);
  __PACKAGE__->add_columns (
    id => { data_type => 'integer', is_auto_increment => 1 },
    data => { data_type => 'varchar', size => 255 },
  );
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->add_unique_constraint(['data']);

EOM
}

{
  package DBICTest::NS::Stress::Schema;

  use base qw/DBICTest::BaseSchema/;

  sub _findallmod {
    return $_[1] eq ( __PACKAGE__ . '::Result' )
      ? ( map { __PACKAGE__ . "::Result::T$_" } 1 .. $::src_count )
      : ()
    ;
  }
}

is (DBICTest::NS::Stress::Schema->sources, 0, 'Start with no sources');

DBICTest::NS::Stress::Schema->load_namespaces;

is (DBICTest::NS::Stress::Schema->sources, $src_count, 'All sources attached');

done_testing;
