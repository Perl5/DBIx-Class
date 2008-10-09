#!/usr/bin/perl

use strict;
use warnings;
use lib qw(lib t/lib);

use DBICTest::Schema;
use SQL::Translator;

my $sql_join_str = '';
if (SQL::Translator->VERSION >= 0.09001) {
    $sql_join_str .= ";";
}
if (SQL::Translator->VERSION >= 0.09) {
    $sql_join_str .= "\n";
}

my $schema = DBICTest::Schema->connect;
print join ($sql_join_str,$schema->storage->deployment_statements($schema, 'SQLite') );
