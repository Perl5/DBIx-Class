BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'admin';

use strict;
use warnings;

use Test::More;
use Test::Exception;


use DBICTest;

use DBIx::Class::Admin;

{ # test data maniplulation functions

  # create a DBICTest so we can steal its connect info
  my $schema = DBICTest->init_schema(
    sqlite_use_file => 1,
  );

  my $storage = $schema->storage;
  $storage = $storage->master
    if $storage->isa('DBIx::Class::Storage::DBI::Replicated');

  my $admin = DBIx::Class::Admin->new(
    schema_class=> "DBICTest::Schema",
    connect_info => $storage->connect_info(),
    quiet  => 1,
    _confirm=>1,
  );
  isa_ok ($admin, 'DBIx::Class::Admin', 'create the admin object');

  $admin->insert('Employee', { name => 'Matt' });
  my $employees = $schema->resultset('Employee');
  is ($employees->count(), 1, "insert okay" );

  my $employee = $employees->find(1);
  is($employee->name(),  'Matt', "insert valid" );

  $admin->update('Employee', {name => 'Trout'}, {name => 'Matt'});

  $employee = $employees->find(1);
  is($employee->name(),  'Trout', "update Matt to Trout" );

  $admin->insert('Employee', {name =>'Aran'});

  my $expected_data = [
    [$employee->result_source->columns() ],
    [1,1,undef,undef,undef,'Trout',undef],
    [2,2,undef,undef,undef,'Aran',undef]
  ];
  my $data;
  lives_ok { $data = $admin->select('Employee', undef, { order_by => 'employee_id' })} 'can retrive data from database';
  is_deeply($data, $expected_data, 'DB matches whats expected');

  $admin->delete('Employee', {name=>'Trout'});
  my $del_rs  = $employees->search({name => 'Trout'});
  is($del_rs->count(), 0, "delete Trout" );
  is ($employees->count(), 1, "left Aran" );
}

done_testing;
