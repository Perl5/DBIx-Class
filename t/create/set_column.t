use warnings;
use strict;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

TODO: {
    local $TODO = 'call accessors when calling create() or update()';

    my $row =
      $schema->resultset('Track')->new_result( { title => 'foo', cd => 1 } );
    $row->increment(1);
    $row->insert;
    is( $row->increment, 2 );

    $row =
      $schema->resultset('Track')
      ->create( { title => 'bar', cd => 1, increment => 1 } );
    is( $row->increment, 2 );

    # $row isa DBICTest::Schema::Track
    $row->get_from_storage;
    is( $row->increment, 2 );

    $row->update( { increment => 3 } );
    $row->get_from_storage;
    is( $row->increment, 4 );

    $row->increment(3);
    $row->get_from_storage;
    is( $row->increment, 4 );

    eval {
        $row =
          $schema->resultset('Track')
          ->create( { title => 'bar', cd => 2, set_increment => 1 } );
    };
    ok( !$@, 'lives ok' );
    is( $row->increment, 1 );

}

done_testing;
