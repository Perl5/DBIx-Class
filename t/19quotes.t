use strict;
use Test::More;
use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 3 );
}

use lib qw(t/lib);

use_ok('DBICTest');

use_ok('DBICTest::HelperRels');

DBICTest->schema->storage->sql_maker->{'quote_char'} = q!'!;
DBICTest->schema->storage->sql_maker->{'name_sep'} = '.';

my $rs = DBICTest::CD->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });

cmp_ok( $rs->count, '==', 1, "join with fields quoted");

