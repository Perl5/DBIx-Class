use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    require DBIx::Class;
    plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for('admin')
      unless DBIx::Class::Optional::Dependencies->req_ok_for('admin');
}

if(use_ok 'DBIx::Class::Admin') {
  my $admin = DBIx::Class::Admin->new(
      include_dirs => ['t/var/dbicadmincrap/lib'],
      schema_class => 'Foo',
      config => { Foo => {} },
      config_stanza => 'Foo'
  );
  lives_ok { $admin->_build_schema } 'should survive attempt to load module located in include_dirs';
  {
    no warnings 'once';
    ok($Foo::loaded);
  }
}

done_testing;
