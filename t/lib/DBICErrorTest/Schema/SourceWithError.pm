package DBICErrorTest::Schema::SourceWithError;

use strict;
use warnings;

use base 'DBIx::Class';
__PACKAGE__->load_components('Core');
__PACKAGE__->table('foo');
#__PACKAGE__->load_components('+DBICErrorTest::SyntaxError');
require DBICErrorTest::ResultSet::WithError;
__PACKAGE__->resultset_class('DBICErrorTest::ResultSet::WithError');

1;
