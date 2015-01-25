use strict;
use warnings;

use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_prettydebug';

use lib qw(t/lib);
use DBICTest;
use Test::More;

BEGIN { delete @ENV{qw(DBIC_TRACE_PROFILE)} }

{
   my $schema = DBICTest->init_schema;

   isa_ok($schema->storage->debugobj, 'DBIx::Class::Storage::Statistics');
}

{
   local $ENV{DBIC_TRACE_PROFILE} = 'console';

   my $schema = DBICTest->init_schema;

   isa_ok($schema->storage->debugobj, 'DBIx::Class::Storage::Debug::PrettyPrint');;
   is($schema->storage->debugobj->_sqlat->indent_string, ' ', 'indent string set correctly from console profile');
}

{
   local $ENV{DBIC_TRACE_PROFILE} = './t/lib/awesome.json';

   my $schema = DBICTest->init_schema;

   isa_ok($schema->storage->debugobj, 'DBIx::Class::Storage::Debug::PrettyPrint');;
   is($schema->storage->debugobj->_sqlat->indent_string, 'frioux', 'indent string set correctly from file-based profile');
}

done_testing;
