package DBICErrorTest::ResultSet::WithError;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

__PACKAGE__->load_components('+DBICErrorTest::SyntaxError');

1;
