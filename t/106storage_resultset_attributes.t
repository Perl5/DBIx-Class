use strict;
use warnings;

use Test::More qw/no_plan/;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DateTime;
use Devel::Dwarn;

my ( $dsn, $user, $pass )
    = @ENV{ map {"DBICTEST_PG_${_}"} qw/DSN USER PASS/ };

plan skip_all => <<'EOM' unless $dsn && $user;
Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test
( NOTE: This test drops and creates tables called 'artist', 'cd',
'timestamp_primary_key_test', 'track', 'casecheck', 'array_test' and
'sequence_test' as well as following sequences: 'pkid1_seq', 'pkid2_seq' and
'nonpkid_seq'. as well as following schemas: 'dbic_t_schema',
'dbic_t_schema_2', 'dbic_t_schema_3', 'dbic_t_schema_4', and 'dbic_t_schema_5')
EOM

my $schema = DBICTest::Schema->connect( $dsn, $user, $pass );
$schema->storage->dbh->{Warn} = 0;

$schema->deploy( { add_drop_table => 1, add_drop_view => 1, debug => 0 } );


### A table

my $flagpole = $schema->resultset('StorageFlagPole');
is_deeply( $flagpole->result_source->resultset_attributes, { storage => { use_insert_returning => 0 }}, "My table resultset does NOT want to use insert returning");
my $flagged_row;

throws_ok(sub { $flagged_row = $flagpole->create( { name => "My name is row." } ) }, qr/no sequence found for storage_flag_pole.id/, "Without insert_returning, insert throws a no-sequence defined error because the PK is not autoinc");
lives_ok { $flagged_row = $flagpole->create( { id => DateTime->now, name => "My name is row." } ) }  "You have to pass the id" ;

lives_ok { $flagged_row->insert } "It can be inserted after you put the id";

### A view

my $flagview = $schema->resultset('StorageFlagPole');
is_deeply( $flagview->result_source->resultset_attributes, { storage => { use_insert_returning => 0 }}, "Upon mere instantiation my view resultset does NOT want to use insert returning");
