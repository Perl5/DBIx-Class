use strict;
use warnings;

use Test::More;

use lib 't/lib';
use DBICTest;

BEGIN {
    require DBIx::Class;
    plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for('admin')
      unless DBIx::Class::Optional::Dependencies->req_ok_for('admin');
}

use_ok 'DBIx::Class::Admin';


done_testing;
