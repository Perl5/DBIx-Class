BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

BEGIN { delete $ENV{DBIC_ASSERT_NO_FAILING_SANITY_CHECKS} }

use strict;
use warnings;

use Test::More;

use DBICTest::Util 'capture_stderr';
use DBICTest;


{
  package DBICTest::Some::BaseResult;
  use base "DBIx::Class::Core";

  # order is important
  __PACKAGE__->load_components(qw( FilterColumn InflateColumn::DateTime ));
}

{
  package DBICTest::Some::Result;
  use base "DBICTest::Some::BaseResult";

  __PACKAGE__->table("sometable");

  __PACKAGE__->add_columns(
    somecolumn => { data_type => "datetime" },
  );
}

{
  package DBICTest::Some::Schema;
  use base "DBIx::Class::Schema";
  __PACKAGE__->schema_sanity_checker("DBIx::Class::Schema::SanityChecker");
  __PACKAGE__->register_class( some_result => "DBICTest::Some::Result" );
}

like(
  capture_stderr {
    DBICTest::Some::Schema->connection(sub {} );
  },
  qr/Class 'DBICTest::Some::Result' was originally using the 'dfs' MRO affecting .+ register_column\(\)/,
  'Proper incorrect composition warning emitted on StdErr'
);

done_testing;
