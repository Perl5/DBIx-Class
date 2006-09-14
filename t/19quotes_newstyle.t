use strict;
use warnings;

use Test::More;
use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 6 );
}

use lib qw(t/lib);

use_ok('DBICTest');
DBICTest->init_schema();

my $dsn = DBICTest->schema->storage->connect_info->[0];

DBICTest->schema->connection($dsn, { quote_char => '`', name_sep => '.' });

my $rs = DBICTest::CD->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });

cmp_ok( $rs->count, '==', 1, "join with fields quoted");

$rs = DBICTest::CD->search({},
            { 'order_by' => 'year DESC'});
{
       eval { $rs->first() };
       like( $@, qr/no such column: year DESC/, "Problem with ORDER BY quotes" );
}

my $order = 'year DESC';
$rs = DBICTest::CD->search({},
            { 'order_by' => \$order });
{
       eval { $rs->first() };
       ok(!$@, "No problem handling ORDER by scalaref" );
}

DBICTest->schema->connection($dsn, { quote_char => [qw/[ ]/], name_sep => '.' });

$rs = DBICTest::CD->search(
           { 'me.year' => 2001, 'artist.name' => 'Caterwauler McCrae' },
           { join => 'artist' });
cmp_ok($rs->count,'==', 1,"join quoted with brackets.");

my %data = (
       name => 'Bill',
       order => '12'
);

DBICTest->schema->connection($dsn, { quote_char => '`', name_sep => '.' });

cmp_ok(DBICTest->schema->storage->sql_maker->update('group', \%data), 'eq', 'UPDATE `group` SET `name` = ?, `order` = ?', "quoted table names for UPDATE");

